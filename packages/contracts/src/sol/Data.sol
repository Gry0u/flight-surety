// "SPDX-License-Identifier: MIT"
pragma solidity ^0.7.3;

import "@openzeppelin/contracts/math/SafeMath.sol";


contract FlightSuretyData {
    using SafeMath for uint;

    //////////////////////// DATA VARIABLES

    // Account used to deploy contract
    address private contractOwner;
    // Blocks all state changes throughout the contract if false
    bool public operational = true;
    // List addresses allowed to call this contract
    mapping(address => bool) public authorizedCallers;

    // Airlines
    struct Airline {
        bool registered;
        bool funded;
    }

    mapping(address => Airline) public airlines;
    uint public registeredAirlinesCount;
    address public firstAirline;

    // Flights
    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 takeOff;
        uint256 landing;
        address airline;
        string flightRef;
        uint price;
        string from;
        string to;
        mapping(address => bool) bookings;
        mapping(address => uint) insurances;

    }

    /* Have to be out of the Flight struct type,
    otherwise can't use FLight constructor in the registerFLight function.
    (unlike mapping object, array argument can't be omitted)
    */
    address[] internal passengers;

    mapping(bytes32 => Flight) public flights;
    bytes32[] public flightKeys;
    uint public indexFlightKeys = 0;

    /* Withdrawals:
    - passengers: insurance claims
    - airlines: flights prices paid by passengers
    */

    mapping(address => uint) public withdrawals;

    ////////////////////////// EVENTS
    event Paid(address recipient, uint amount);
    event Funded(address airline);
    event AirlineRegistered(address origin, address newAirline);
    event Credited(address passenger, uint amount);


    ///////////////////////// CONSTRUCTOR
    constructor(address _firstAirline) {
        contractOwner = msg.sender;

        // register first airline at deployment
        firstAirline = _firstAirline;
        registeredAirlinesCount = 1;
        airlines[firstAirline].registered = true;
    }

    ////////////////////////// MODIFIERS
    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        // All modifiers require an "_" which indicates where the function body will be added
        _;
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    // restrict function calls to previously authorized addresses
    modifier callerAuthorized() {
        require(authorizedCallers[msg.sender] == true, "Address not authorized to call this function");
        _;
    }

    // To avoid spending gas trying to put the contract in a state it already is in
    modifier differentModeRequest(bool status) {
        require(status != operational, "Contract already in the state requested");
        _;
    }

    modifier flightRegistered(bytes32 flightKey) {
        require(flights[flightKey].isRegistered, "This flight does not exist");
        _;
    }

    modifier valWithinRange(uint val, uint low, uint up) {
        require(val < up, "Value higher than max allowed");
        require(val > low, "Value lower than min allowed");
        _;
    }

    /* do not process a flight more than once,
    which could e.g result in the passengers being credited their insurance amount twice.
    */
    modifier notYetProcessed(bytes32 flightKey) {
        require(flights[flightKey].statusCode == 0, "This flight has already been processed");
        _;
    }
    /////////////////////////// UTILITY FUNCTIONS
    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */

    function setOperatingStatus(bool mode) external requireContractOwner
    differentModeRequest(mode)
    {
        operational = mode;
    }

    // function to authorize addresses (especially the App contract!) to call functions from flighSuretyData contract
    function authorizeCaller(address callerAddress)
    external
    requireContractOwner
    requireIsOperational
    {
        authorizedCallers[callerAddress] = true;
    }

    function hasFunded(address airlineAddress)
    external
    view
    returns (bool _hasFunded)
    {
        _hasFunded = airlines[airlineAddress].funded;
    }

    function isRegistered(address airlineAddress)
    external
    view
    returns (bool _registered)
    {
        _registered = airlines[airlineAddress].registered;
    }

    function getFlightKey
    (
        string calldata flightRef,
        string calldata destination,
        uint256 timestamp
    )
    public
    pure
    returns(bytes32)
    {
        return keccak256(abi.encodePacked(flightRef, destination, timestamp));
    }

    function paxOnFlight
    (
        string calldata flightRef,
        string calldata destination,
        uint256 timestamp,
        address passenger
    )
    public
    view
    returns(bool onFlight)
    {
        bytes32 flightKey = getFlightKey(flightRef, destination, timestamp);
        onFlight = flights[flightKey].bookings[passenger];
    }

    function subscribedInsurance
    (
        string calldata flightRef,
        string calldata destination,
        uint256 timestamp,
        address passenger
    )
    public
    view
    returns(uint amount)
    {
        bytes32 flightKey = getFlightKey(flightRef, destination, timestamp);
        amount = flights[flightKey].insurances[passenger];
    }

    function getFlightPrice(bytes32 flightKey)
    external
    view
    returns (uint price)
    {
        price = flights[flightKey].price;
    }

    //////////////////////// SMART CONTRACT FUNCTIONS
   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */
    function registerAirline
    (
        address airlineAddress,
        address originAddress
    )
    external
    requireIsOperational
    callerAuthorized
    {
        registeredAirlinesCount++;
        airlines[airlineAddress].registered = true;
        emit AirlineRegistered(originAddress, airlineAddress);
    }

    function registerFlight
    (
        uint _takeOff,
        uint _landing,
        string calldata _flight,
        uint _price,
        string calldata _from,
        string calldata _to,
        address originAddress
    )
    external
    requireIsOperational
    callerAuthorized
    {
        require(_takeOff > block.timestamp, "A flight cannot take off in the past");
        require(_landing > _takeOff, "A flight cannot land before taking off");

        bytes32 flightKey = keccak256(abi.encodePacked(_flight, _to, _landing));
        Flight storage flight = flights[flightKey];
        flight.isRegistered = true;  
        flight.statusCode = 0;
        flight.takeOff = _takeOff;
        flight.landing = _landing; 
        flight.airline = originAddress;
        flight.flightRef = _flight;
        flight.price= _price;
        flight.from=_from;
        
        flightKeys.push(flightKey);
        indexFlightKeys = flightKeys.length.sub(1);
        // event emission in app contract
    }


   /**
    * @dev Passenger Buys insurance for a flight
    *
    */
    function book(bytes32 flightKey, uint amount, address originAddress)
    external
    requireIsOperational
    callerAuthorized
    flightRegistered(flightKey)
    payable
    {
        Flight storage flight = flights[flightKey];
        flight.bookings[originAddress] = true;
        flight.insurances[originAddress] = amount;
        passengers.push(originAddress);
        withdrawals[flight.airline] = flight.price;
    }

    function creditInsurees(bytes32 flightKey)
    internal
    requireIsOperational
    flightRegistered(flightKey)
    {
        // get flight
        Flight storage flight = flights[flightKey];
        // loop over passengers and credit them their insurance amount
        for (uint i = 0; i < passengers.length; i++) {
            withdrawals[passengers[i]] = flight.insurances[passengers[i]];
            emit Credited(passengers[i], flight.insurances[passengers[i]]);
        }
    }


    /**
     *  @dev Transfers eligible payout funds to insuree or airline
     *
    */
    function pay(address payable originAddress)
    external
    requireIsOperational
    callerAuthorized
    {
        // Check-Effect-Interaction pattern to protect against re entrancy attack
        // Check
        require(withdrawals[originAddress] > 0, "No amount to be transferred to this address");
        // Effect
        uint amount = withdrawals[originAddress];
        withdrawals[originAddress] = 0;
        // Interaction
        originAddress.transfer(amount);
        emit Paid(originAddress, amount);
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */
    function fund(address originAddress)
    public
    requireIsOperational
    callerAuthorized
    payable
    {
        airlines[originAddress].funded = true;
        emit Funded(originAddress);
    }

    function processFlightStatus
    (
        bytes32 flightKey,
        uint8 statusCode
    )
    external
    flightRegistered(flightKey)
    requireIsOperational
    callerAuthorized
    notYetProcessed(flightKey)
    {
        // Check (modifiers)
        Flight storage flight = flights[flightKey];
        // Effect
        flight.statusCode = statusCode;
        // Interact
        // 20 = "flight delay due to airline"
        if (statusCode == 20) {
            creditInsurees(flightKey);
        }
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    receive() external callerAuthorized payable
    {
        require(msg.data.length == 0);
        fund(msg.sender);
    }
}
