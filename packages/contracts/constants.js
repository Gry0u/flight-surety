const { ethers } = require('hardhat')
const { expect } = require('chai')
const { parseEther } = ethers.utils

exports.expect = expect
exports.ethers = ethers
exports.minFund = parseEther('10')
exports.insurancePayment = parseEther('0.1')
exports.ticketPrice = parseEther('0.5')

const takeOff = Math.floor(Date.now() / 1000) + 1000

exports.takeOff = takeOff
exports.landing = takeOff + 1000
exports.timestamp = takeOff + 1000
exports.from = 'HAM'
exports.to = 'PAR'
exports.flightRef = 'AF0187'

exports.fee = parseEther('1')
