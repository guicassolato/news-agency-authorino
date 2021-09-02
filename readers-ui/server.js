const express = require('express')
const axios = require('axios')
const { v4: uuidv4 } = require('uuid')

const { ENDPOINT, NEWS_API_ENDPOINT, KEYCLOAK_REALM, CLIENT_ID, CLIENT_SECRET } = process.env

const app = express()

var requestId

app.all('*', (req, _, next) => {
  requestId = uuidv4()
  console.log(`[${requestId}] ${req.method} ${req.path}`)
  next()
})

app.get('/auth', (req, res) => {
  const requestToken = req.query.code
  console.log(`[${requestId}] Requesting token for code ${requestToken}`)

  const params = new URLSearchParams()
  params.append('grant_type', 'authorization_code')
  params.append('code', requestToken)
  params.append('client_id', CLIENT_ID)
  params.append('client_secret', CLIENT_SECRET)
  params.append('redirect_uri', `${ENDPOINT}/auth`)

  axios.post(`${KEYCLOAK_REALM}/protocol/openid-connect/token`, params).then(response => {
    const accessToken = response.data.access_token
    console.log(`[${requestId}] Serving access token ${accessToken}`)
    res.cookie('ACCESS-TOKEN', accessToken)
    res.redirect(`/`)
  }).catch(error => {
    console.log('Error: ' + error.message)
  })
})

const pageContent = (data) => {
  const dataAttributes = Object.entries(data).map(attr => `data-${attr[0]}="${attr[1]}"`).join(' ')

  return `<!DOCTYPE html>
<html>
  <head>
    <title>Readers UI</title>
    <link rel="shortcut icon" type="image/x-icon" href="favicon.ico"/>
    <link rel="stylesheet" type="text/css" href="webapp.css"/>
    <script src="webapp.js" defer="defer"></script>
  </head>
  <body ${dataAttributes}>
    <h1>News Agency · Readers UI</h1>
    <ul id="user-menu"></ul>
    <ul id="app-menu"></ul>
    <div>Latest news:</div>
    <pre id="news"></pre>
  </body>
</html>`
}

app.use('/', express.static(__dirname + '/public'))
app.use((_, res) => res.send(pageContent({
  'readers-ui-endpoint': ENDPOINT,
  'news-api-endpoint': NEWS_API_ENDPOINT,
  'keycloak-realm': KEYCLOAK_REALM
})))

const server = app.listen(8888, () => {
  console.log("Listening on port %s", server.address().port)
})
