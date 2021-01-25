import express from 'express'
import cors from 'cors'
const middlewares = [cors(), express.json()]

export { middlewares }
