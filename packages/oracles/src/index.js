import { app } from './app'
import { Oracles } from './oracles'

const NUMBER_OF_ACCOUNTS = 50 // update in truffle.js and start ganacle-cli with the right number of accounts if necessary
const NUMBER_OF_ORACLES = 30

const start = () => {
  Oracles.init(NUMBER_OF_ORACLES)
  app.listen(3000, () => console.log('Oracles server 👂 on port 3000'))
}

start()
