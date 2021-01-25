import { Router } from 'express'

const router = Router()

router.get('/api', (_, res) => {
  res.send('An API for use with your Dapp!')
})

export { router as rootRouter }
