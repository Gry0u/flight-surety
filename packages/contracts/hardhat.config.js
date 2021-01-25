require('dotenv').config()
require('@nomiclabs/hardhat-waffle')

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

const INFURA_PROJECT_ID = process.env.INFURA_PROJECT_ID
const ROPSTEN_PRIVATE_KEY = process.env.RINKEBY_PRIVATE_KEY

module.exports = {
  networks: {
    hardhat: {
      accounts: {
        count: 30
      }
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${INFURA_PROJECT_ID}`,
      accounts: [`0x${ROPSTEN_PRIVATE_KEY}`]
    }
  },
  solidity: '0.7.3',
  paths: {
    sources: './src/sol',
    tests: './src/test',
    artifacts: './src/artifacts',
    cache: './src/cache'
  }
}
