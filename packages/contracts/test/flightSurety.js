const { expect } = require('chai')
const { ethers } = require('hardhat')
const { parseEther } = ethers.utils

describe('Flight Surety Tests', async accounts => {
  var config
  // Operations and Settings
  // !!!!Warning: .toWei() returns a string
  const minFund = parseEther('10')
  const insurancePayment = parseEther('0.1')
  const ticketPrice = parseEther('0.5')
  const takeOff = Math.floor(Date.now() / 1000) + 1000
  const landing = takeOff + 1000
  const from = 'HAM'
  const to = 'PAR'
  const flightRef = 'AF0187'

  let dataContract
  let appContract
  let firstAirline
  let addr1
  let addrs

  beforeEach(async () => {
    dataFactory = await ethers.getContractFactory(
      'src/sol/Data.sol:FlightSuretyData'
    )
    appFactory = await ethers.getContractFactory(
      'src/sol/App.sol:FlightSuretyApp'
    )
    ;[owner, firstAirline, addr1, addr2, ...addrs] = await ethers.getSigners()

    dataContract = await dataFactory.deploy(firstAirline.address)
    appContract = await appFactory.deploy(dataContract.address)

    // authorize App contract to call Data contract
    await dataContract.authorizeCaller(appContract.address)
  })

  describe('Deployment', () => {
    it('data contract is operational', async () => {
      expect(await dataContract.operational()).to.be.true
    })

    it('app contract is operational', async () => {
      expect(await appContract.operational()).to.be.true
    })

    it('app contract is authorized to call data contract', async () => {
      const authorized = await dataContract.authorizedCallers(
        appContract.address
      )
      expect(authorized).to.be.true
    })

    it('first airline is registered', async () => {
      expect(await dataContract.firstAirline()).to.equal(firstAirline.address)
      expect(await dataContract.registeredAirlinesCount()).to.equal(1)

      const registered = (await dataContract.airlines(firstAirline.address))
        .registered
      expect(registered).to.be.true
    })
  })

  describe('Data Contract', () => {
    it('owner can set operational status to false', async () => {
      await dataContract.setOperatingStatus(false)
      expect(await dataContract.operational()).to.be.false
    })

    it('not owner cannot change operational status', async () => {
      let accessDenied = false
      try {
        await dataContract.connect(addr1).setOperatingStatus(false)
      } catch (e) {
        accessDenied = true
      }
      expect(accessDenied).to.be.true
    })

    it('blocks function using requireIsOperational modifier when operational status is false', async () => {
      let reverted = false
      await dataContract.setOperatingStatus(false)
      try {
        await dataContract.authorizeCaller(addr1)
      } catch (e) {
        reverted = true
      }
      expect(reverted).to.be.true
    })

    it('can authorize a caller', async () => {
      expect(await dataContract.authorizedCallers(addr1.address)).to.be.false

      await dataContract.authorizeCaller(addr1.address)

      expect(await dataContract.authorizedCallers(addr1.address)).to.be.true
    })
  })
  describe('App contract', () => {
    it('airline must provide funding before registering another one', async () => {
      try {
        await appContract.connect(firstAirline).registerAirline(addr1.address)
      } catch (error) {
        expect(
          error.message.includes('Airline must provide funding'),
          'Error: wrong revert message'
        )
      }
    })

    it('airline can provide funding', async () => {
      const balanceBefore = await dataContract.provider.getBalance(
        dataContract.address
      )

      await appContract.connect(firstAirline).fund({ value: minFund })

      const funded = (await dataContract.airlines(firstAirline.address)).funded
      const balanceAfter = await dataContract.provider.getBalance(
        dataContract.address
      )

      expect(balanceBefore + minFund).to.equal(balanceAfter)
      expect(funded).to.be.true
    })

    it('airline cannot register another airline if it is not registered', async () => {
      try {
        await appContract.connect(addrs[0]).registerAirline(addrs[1].address)
      } catch (error) {
        expect(
          error.message.includes('Airline must be registered'),
          `${error.message}`
        )
      }
    })

    it('only first Airline can register an airline when less than 4 airlines are registered', async () => {
      // register one other airline
      await appContract.connect(firstAirline).fund({ value: minFund })
      await appContract.connect(firstAirline).registerAirline(addrs[0].address)

      expect(await dataContract.registeredAirlinesCount()).to.equal(2)
      const registered = (await dataContract.airlines(addrs[0].address))
        .registered
      expect(registered).to.be.true

      // newly registered airline provides funding
      await appContract.connect(addrs[0]).fund({ value: minFund })

      try {
        await appContract.connect(addrs[0]).registerAirline(addrs[1].address)
      } catch (error) {
        expect(error.message.includes('Less than 4 airlines registered'))
      }
    })

    it('(multiparty) Starting from 4 airlines, half of the registered airlines must agree to register a new one', async () => {
      // register 3 new airlines
      await appContract.connect(firstAirline).fund({ value: minFund })
      await appContract.connect(firstAirline).registerAirline(addrs[0].address)
      await appContract.connect(firstAirline).registerAirline(addrs[1].address)
      await appContract.connect(firstAirline).registerAirline(addrs[2].address)
      expect(await dataContract.registeredAirlinesCount()).to.equal(4)

      // First airline cannot register 4th one alone
      // calling register only casts 1 vote
      await appContract.connect(firstAirline).registerAirline(addrs[3].address)
      expect(await dataContract.registeredAirlinesCount()).to.equal(4)
      expect((await dataContract.airlines(addrs[3].address)).registered).to.be
        .false

      // 4 airlines, 2 votes required, 1 vote left
      const votes = await appContract.votesLeft(addrs[3].address)
      expect(votes).to.equal(1)

      // Cannot vote twice
      try {
        await appContract
          .connect(firstAirline)
          .registerAirline(addrs[3].address)
      } catch (error) {
        expect(
          error.message.includes('Caller cannot call this function twice'),
          'Error: wrong revert message'
        )
      }

      // Let other airline vote
      await appContract.connect(addrs[0]).fund({ value: minFund })
      await appContract.connect(addrs[0]).registerAirline(addrs[3].address)

      expect(await dataContract.registeredAirlinesCount()).to.equal(5)
      expect((await dataContract.airlines(addrs[3].address)).registered).to.be
        .true
    })

    it('registering a flight requires funding', async () => {
      try {
        await appContract
          .connect(firstAirline)
          .registerFlight(takeOff, landing, flightRef, ticketPrice, from, to)
      } catch (error) {
        expect(error.message.includes('must provide funding'))
      }
    })

    it('airline can register a flight', async () => {
      await appContract.connect(firstAirline).fund({ value: minFund })
      const tx = await appContract
        .connect(firstAirline)
        .registerFlight(takeOff, landing, flightRef, ticketPrice, from, to)

      const flightKey = await dataContract.getFlightKey(flightRef, to, landing)
      const flight = await dataContract.flights(flightKey)

      expect(flight.isRegistered, 'Error: flight was not registered')
      expect(flight.price).to.equal(ticketPrice)
      expect(tx)
        .to.emit(appContract, 'FlightRegistered')
        .withArgs(flightRef, to, landing)
    })

    it('can book a flight and subscribe an insurance', async () => {
      // register flight
      await appContract.connect(firstAirline).fund({ value: minFund })
      await appContract
        .connect(firstAirline)
        .registerFlight(takeOff, landing, flightRef, ticketPrice, from, to)

      // book flight
      await appContract
        .connect(addrs[1])
        .book(flightRef, to, landing, insurancePayment, {
          value: ticketPrice.add(insurancePayment)
        })

      const paxOnFlight = await dataContract.paxOnFlight(
        flightRef,
        to,
        landing,
        addrs[1].address
      )
      const insuranceCredit = await dataContract.subscribedInsurance(
        flightRef,
        to,
        landing,
        addrs[1].address
      )

      expect(paxOnFlight, 'Flight booking unsuccessful')
      expect(
        insuranceCredit,
        'Insurance amount not recorded correctly'
      ).to.equal(insurancePayment.mul(3).div(2))
    })

    it('airline can withdraw their credited amount (from bought flight tickets)', async () => {
      // register flight
      await appContract.connect(firstAirline).fund({ value: minFund })
      await appContract
        .connect(firstAirline)
        .registerFlight(takeOff, landing, flightRef, ticketPrice, from, to)

      // book flight
      await appContract
        .connect(addrs[1])
        .book(flightRef, to, landing, insurancePayment, {
          value: ticketPrice.add(insurancePayment)
        })

      const balanceBefore = await dataContract.provider.getBalance(
        firstAirline.address
      )

      tx = await appContract.connect(firstAirline).withdraw()

      const balanceAfter = await dataContract.provider.getBalance(
        firstAirline.address
      )

      expect(+balanceAfter).to.be.greaterThan(+balanceBefore)

      expect(tx)
        .to.emit(appContract, 'WithdrawRequest')
        .withArgs(firstAirline.address)
    })
  })
})
