import { Router } from 'express'

const router = Router()

router.get('/response/:ref.:dest.:landing', async (req, res) => {
  const key = await flightSuretyData.methods
    .getFlightKey(req.params.ref, req.params.dest, req.params.landing)
    .call()
  const response = await flightSuretyApp.methods.oracleResponses(key).call()
  res.send(response)
})

export { router as responseRouter }
