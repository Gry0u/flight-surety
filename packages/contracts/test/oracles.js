const { expect } = require('chai')
const importAll = require('../importAll')
importAll().from('./constants')

describe('Oracles', () => {
  const TEST_ORACLES_COUNT = 15
  const STATUS_CODE_LATE_AIRLINE = 20

  let dataContract
  let appContract
  let firstAirline
  let addr1
  let addrs

  before(async () => {
    dataFactory = await ethers.getContractFactory(
      'src/sol/Data.sol:FlightSuretyData'
    )
    appFactory = await ethers.getContractFactory(
      'src/sol/App.sol:FlightSuretyApp'
    )
    ;[owner, firstAirline, addr1, ...addrs] = await ethers.getSigners()

    // deploy contracts
    dataContract = await dataFactory.deploy(firstAirline.address)
    appContract = await appFactory.deploy(dataContract.address)

    // authorize App contract to call Data contract
    await dataContract.authorizeCaller(appContract.address)

    // provide funding
    await appContract.connect(firstAirline).fund({ value: minFund })

    // register flight
    await appContract
      .connect(firstAirline)
      .registerFlight(takeOff, timestamp, flightRef, ticketPrice, from, to)

    // book flight
    await appContract
      .connect(addr1)
      .book(flightRef, to, timestamp, insurancePayment, {
        value: ticketPrice.add(insurancePayment)
      })
  })

  it('can register oracles', async () => {
    for (let a = 0; a < TEST_ORACLES_COUNT; a++) {
      const tx = await appContract
        .connect(addrs[a])
        .registerOracle({ value: fee })

      let result = await appContract.connect(addrs[a]).getMyIndexes()
      // console.log(`Oracle registered ${result}`)

      expect(tx).to.emit(appContract, 'OracleRegistered').withArgs(result)
    }
  })

  it('can request flight status, process it and credit insuree', async () => {
    // Submit a request for oracles to get status information for a flight
    const tx1 = await appContract.fetchFlightStatus(flightRef, to, timestamp)
    expect(tx1).to.emit(appContract, 'OracleRequest')

    let tx2
    /*
      Since the Index assigned to each test account is opaque by design,
      loop through all the accounts
      and for each account loop though all its Indexes and submit a response.
      The contract will reject a submission if it was not requested.
      While sub-optimal, it's a good test for that feature
    */

    for (let a = 1; a < TEST_ORACLES_COUNT; a++) {
      // Get oracle information
      const oracleIndexes = await appContract.connect(addrs[a]).getMyIndexes()

      for (let idx = 0; idx < 3; idx++) {
        // Submit a response...it will only be accepted if there is an Index match
        try {
          tx2 = await appContract
            .connect(addrs[a])
            .submitOracleResponse(
              oracleIndexes[idx],
              flightRef,
              to,
              timestamp,
              STATUS_CODE_LATE_AIRLINE
            )

          // Check OracleReport event, emitted if index match
          expect(tx)
            .to.emit(appContract, 'OracleReport')
            .withArgs(flightRef, to, timestamp, STATUS_CODE_LATE_AIRLINE)
          break
        } catch (e) {
          if (e.message.includes('request is closed')) {
            expect(tx2)
              .to.emit(appContract, 'FlightStatusInfo')
              .withArgs(flightRef, to, timestamp, STATUS_CODE_LATE_AIRLINE)
            expect(tx2).to.emit(appContract, 'FlightProcessed')
            break
          }
          continue
        }
      }
    }
  })

  it('closes request after enough concurring answers have been received', async () => {
    const key = await dataContract.getFlightKey(flightRef, to, timestamp)
    const request = await appContract.oracleResponses(key)
    expect(request.isOpen, 'Request should be closed').to.be.false
  })

  it('Updates Flight Status after enough concurring answers have been received', async () => {
    const key = await dataContract.getFlightKey(flightRef, to, timestamp)
    const flight = await dataContract.flights(key)
    expect(flight.statusCode).to.equal(STATUS_CODE_LATE_AIRLINE)
  })

  it('passenger can withdraw credited insurance amount', async () => {
    const balanceBefore = await dataContract.provider.getBalance(addr1.address)

    await appContract.connect(addr1).withdraw()

    const balanceAfter = await dataContract.provider.getBalance(addr1.address)
    expect(+balanceAfter).to.be.greaterThan(+balanceBefore)
  })
})
