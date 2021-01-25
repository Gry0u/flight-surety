import express from 'express'

import { router } from './routes'
import { middlewares } from './middlewares'

const app = express()

app.use([...middlewares, router])

export { app }
