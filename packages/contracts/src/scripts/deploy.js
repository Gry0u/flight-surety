const { takeOff, minFund } = require('../constants')
const importAll = require('../importAll')
importAll().from('./constants')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying contracts with the account:', deployer.address)
  console.log('Account balance:', (await deployer.getBalance()).toString())

  const Data = await ethers.getContractFactory(
    'src/sol/Data.sol:FlightSuretyData'
  )
  const App = await ethers.getContractFactory('src/sol/App.sol:FlightSuretyApp')
  const data = await Data.deploy(deployer.address) // deployer is first account
  const app = await App.deploy(data.address)

  console.log('FlightSurety Data contract address:', data.address)
  console.log('FlightSurety App contract address:', app.address)

  console.log('Authorize app contract to call Data contract')
  await data.authorizeCaller(app.address)

  console.log('Provide funding for 1st airline (deployer = 1st airline)')
  await app.fund({ value: minFund, gasLimit: 100000 })

  console.log(
    `Register flight ${flightRef} from ${from} to ${to}, takeoff ${takeOff}`
  )
  await app.registerFlight(
    takeOff,
    timestamp,
    flightRef,
    ticketPrice,
    from,
    to,
    { gasLimit: 100000 }
  )
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
