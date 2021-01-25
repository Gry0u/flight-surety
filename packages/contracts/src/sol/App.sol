// "SPDX-License-Identifier: MIT"
pragma solidity ^0.7.3;

/* It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info:
https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/
*/

import "@openzeppelin/contracts/math/SafeMath.sol";


// FlightSuretyData Interface contract
abstract contract FlightSuretyData {

    function registerAirline(address airlineAddress, address originAddress) virtual external;
    function fund(address originAddress) virtual external payable;

    function registerFlight
    (
        uint takeOff,
        uint landing,
        string calldata flightRef,
        uint price,
        string calldata from,
        string calldata to,
        address originAddress
    )
    virtual
    external;

    function book(bytes32 flightKey, uint amount, address originAddress) external payable virtual;
    function pay(address originAddress) virtual external;
    function processFlightStatus(bytes32 flightKey, uint8 status)  external virtual;
    function getFlightPrice(bytes32 flightKey) external view virtual returns (uint);
    function hasFunded(address airlineAddress) external view virtual returns (bool);
    function isRegistered(address airlineAddress) external view virtual returns (bool);
    function registeredAirlinesCount() external view virtual returns (uint);
    function firstAirline() external view virtual returns (address);


}


contract FlightSuretyApp {
    // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)
    using SafeMath for uint256;

    ///////////////////////////// APP VARIABLES
    /* Contract upgradability: app contract variables are separated from contract data variables.
    App variables might have to be updated or changed because of business rules changes.
    In this case a new updated App contract would be deployed.
    On the other hand, the linked Data contract isn't changed or redeployed.
    */

    // State var for data contract
    FlightSuretyData flightSuretyData;

    // minimum funding amount
    uint public minFund = 1 ether;

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    // Account used to deploy contract
    address private contractOwner;
    // Contract control flag
    bool public operational;

    // Multi-party consensus - part of app logic
    // mapping instead of an array I want to count not only multicalls but multicalls per to-be-added airline
    mapping(address => address[]) internal votes;

    /////////////////////////////// EVENTS

    event FlightRegistered(string flightRef, string to, uint landing);
    event WithdrawRequest(address recipient);
    event FlightProcessed(string flightRef, string destination, uint timestamp, uint8 statusCode);

    /////////////////////////////// MODIFIERS

    // Contract "pausing" functionality
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        // All modifiers require an "_" which indicates where the function body will be added
        _;
    }

    // avoid spending unecessary gas if requested state changed if the same as the current one
    modifier differentModeRequest(bool status) {
        require(status != operational, "Contract already in the state requested");
        _;
    }

    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    // Part of app contract (business rule that might change)
    modifier enoughFund() {
        require(msg.value >= minFund, "Minimun funding amount is 10 ETH");
        _;
    }

    modifier valWithinRange(uint val, uint low, uint up) {
        require(val < up, "Value higher than max allowed");
        require(val > low, "Value lower than min allowed");
        _;
    }

    modifier paidEnough(uint _price) {
        require(msg.value >= _price, "Value sent does not cover the price!");
        _;
    }

    modifier checkValue(uint _price) {
        uint amountToReturn = msg.value - _price;
        msg.sender.transfer(amountToReturn);
        _;
    }

    modifier airlineRegistered() {
        require(
            flightSuretyData.isRegistered(msg.sender),
            "Airline must be registered before being able to perform this action"
        );
        _;
    }

    modifier airlineFunded() {
        require(
            flightSuretyData.hasFunded(msg.sender),
            "Airline must provide funding before being able to perform this action"
        );
        _;
    }
    //////////////////////////////// CONSTRUCTOR

    constructor(address dataContractAddress) {
        operational = true;
        contractOwner = msg.sender;
        flightSuretyData = FlightSuretyData(dataContractAddress);
    }

    //////////////////////////// UTILITY FUNCTIONS
    function setOperatingStatus(bool mode) external requireContractOwner
    differentModeRequest(mode)
    {
        operational = mode;
    }

    function votesLeft(address airlineToBeAdded)
    public
    view
    returns (uint remainingVotes)
    {
        uint registeredVotes = votes[airlineToBeAdded].length;
        uint threshold = flightSuretyData.registeredAirlinesCount().div(2);
        remainingVotes = threshold.sub(registeredVotes);
    }

    ///////////////////////////// SMART CONTRACT FUNCTIONS

    function registerAirline(address airlineAddress)
    external
    requireIsOperational
    airlineRegistered
    airlineFunded
    {
        // only first Airline can register a new airline when less than 4 airlines are registered
        if (flightSuretyData.registeredAirlinesCount() < 4) {
            require(
                flightSuretyData.firstAirline() == msg.sender,
                "Less than 4 airlines registered: only first airline registered can register new ones");
            flightSuretyData.registerAirline(airlineAddress, msg.sender);
        } else {
            // multi party consensus
            bool isDuplicate = false;
            for (uint i=0; i < votes[airlineAddress].length; i++) {
                if (votes[airlineAddress][i] == msg.sender) {
                    isDuplicate = true;
                    break;
                }
            }
            require(!isDuplicate, "Caller cannot call this function twice");
            votes[airlineAddress].push(msg.sender);

            if (votesLeft(airlineAddress) == 0) {
                votes[airlineAddress] = new address[](0);
                flightSuretyData.registerAirline(airlineAddress, msg.sender);
            }
        }
    }

    function fund()
    external
    airlineRegistered
    enoughFund
    requireIsOperational
    payable
    {
        flightSuretyData.fund{value:msg.value}(msg.sender);
    }

    function registerFlight
    (
        uint takeOff,
        uint landing,
        string calldata flightRef,
        uint price,
        string calldata from,
        string calldata to
    )
    external
    requireIsOperational
    airlineFunded
    {
        flightSuretyData.registerFlight(
            takeOff,
            landing,
            flightRef,
            price,
            from,
            to,
            msg.sender
        );
        emit FlightRegistered(flightRef, to, landing);
    }

    function book
    (
        string calldata _flight,
        string calldata _to,
        uint _landing,
        uint amount
    )
    external
    valWithinRange(amount, 0, 1.05 ether) // +0.05 to cover gas costs
    paidEnough(flightSuretyData.getFlightPrice(getFlightKey(_flight, _to, _landing)).add(amount))
    checkValue(flightSuretyData.getFlightPrice(getFlightKey(_flight, _to, _landing)).add(amount))
    requireIsOperational
    payable
    {
        bytes32 flightKey= getFlightKey(_flight, _to, _landing);

        flightSuretyData.book{value: msg.value}(flightKey, amount.mul(3).div(2), msg.sender);
    }

    function withdraw()
    external
    requireIsOperational
    {
        flightSuretyData.pay(msg.sender);
        emit WithdrawRequest(msg.sender);
    }

   //Called after oracle has updated flight status
    function processFlightStatus
    (
        string calldata flightRef,
        string calldata destination,
        uint256 timestamp,
        uint8 statusCode
    )
    internal
    requireIsOperational
    {
        // generate flightKey
        bytes32 flightKey = getFlightKey(flightRef, destination, timestamp);
        flightSuretyData.processFlightStatus(flightKey, statusCode);

        emit FlightProcessed(flightRef, destination, timestamp, statusCode);
    }


    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus
    (
        string calldata flight,
        string calldata destination,
        uint256 timestamp
    )
    external
    {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = getFlightKey(flight, destination, timestamp);
        ResponseInfo storage responseInfo = oracleResponses[key];
        responseInfo.requester = msg.sender;
        responseInfo.isOpen = true; 

        emit OracleRequest(index, flight, destination, timestamp);
    }

////////////////////// START ORACLE MANAGEMENT REGION
    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint8 private constant MIN_RESPONSES = 3;

    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
        // This lets us group responses and identify
        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(flight, destination, timestamp)
    mapping(bytes32 => ResponseInfo) public oracleResponses;

    event OracleRegistered(uint8[3] indexes);

    // Event fired each time an oracle submits a response
    event OracleReport(string flight, string destination, uint256 timestamp, uint8 status);
    // Event fired when number of identical responses reaches the threshold: response is accepted and is processed
    event FlightStatusInfo(string flight, string destination, uint256 timestamp, uint8 status);


    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, string flight, string destination, uint256 timestamp);

    // Register an oracle with the contract
    function registerOracle() external payable
    {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({
            isRegistered: true,
            indexes: indexes
        });
        emit OracleRegistered(indexes);
    }

    function getMyIndexes() external view returns(uint8[3] memory)
    {
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse
    (
        uint8 index,
        string calldata flight,
        string calldata destination,
        uint256 timestamp,
        uint8 statusCode
    )
    external
    {
        require(
            (oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index),
            "Index does not match oracle request"
        );


        bytes32 key = getFlightKey(flight, destination, timestamp);
        require(
            oracleResponses[key].isOpen,
            "Flight or timestamp do not match oracle request. Or request is closed (enough responses received)");

        oracleResponses[key].responses[statusCode].push(msg.sender);
        emit OracleReport(flight, destination, timestamp, statusCode);

        /* Information isn't considered verified until at least
        MIN_RESPONSES oracles respond with the *** same *** information
        */
        if (oracleResponses[key].responses[statusCode].length == MIN_RESPONSES) {
            // close responseInfo
            oracleResponses[key].isOpen = false;
            emit FlightStatusInfo(flight, destination, timestamp, statusCode);
            // Handle flight status as appropriate
            processFlightStatus(flight, destination, timestamp, statusCode);
        }
    }

    function getFlightKey
    (
        string calldata flightRef,
        string calldata destination,
        uint256 timestamp
    )
    internal
    pure
    returns(bytes32)
    {
        return keccak256(abi.encodePacked(flightRef, destination, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account) internal returns(uint8[3] memory)
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while (indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account) internal returns (uint8)
    {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(
            uint256(
                keccak256(
                    abi.encodePacked(blockhash(block.number - nonce++),
                    account)
                )
            ) % maxValue);

        if (nonce > 250) {
            nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

//////////////////////// END ORACLE MANAGEMENT REGION

}
