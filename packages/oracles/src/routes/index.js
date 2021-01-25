import { Router } from 'express'

import { flightsRouter } from './flights'
import { responseRouter } from './response'
import { rootRouter } from './root'

const router = Router()

router.use([rootRouter, flightsRouter, responseRouter])

export { router }
