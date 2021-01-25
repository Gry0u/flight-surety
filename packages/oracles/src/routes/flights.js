import { Router } from 'express'

const router = Router()

router.get('/flights', (req, res) => {
  res.json(Server.flights)
})

router.get('/flight/:ref.:dest.:landing', async (req, res) => {
  const key = await flightSuretyData.methods
    .getFlightKey(req.params.ref, req.params.dest, req.params.landing)
    .call()
  const flight = await flightSuretyData.methods.flights(key).call()
  res.send(flight)
})

export { router as flightsRouter }
