const ACCESS_TOKEN_COOOKIE_NAME = 'ACCESS-TOKEN'

var userOperations = []

const handleResponse = response => {
  if (response.ok) {
    return response
  }

  var message = `${response.status} ${response.statusText}`

  for (var header of response.headers.entries()) {
    if (header[0] === 'x-ext-auth-reason') {
      message += ` (reason: ${header[1]})`
    }
  }

  throw new Error(message)
}

const processResponseData = (resp) => {
  const { title, path, data } = resp
  renderNewsContent(data)
  window.history.pushState(data, title, path)
}

window.addEventListener('popstate', (event) => renderNewsContent(event.state))

const renderNewsContent = (content) => {
  const newsContent = content === String ? content : JSON.stringify(content, null, 2)
  document.getElementById('news').innerHTML = newsContent
}

const getCookie = (name) => {
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) return parts.pop().split(';').shift();
}

const sendApiRequest = (uri, method, title, path) => {
  const state = { title: title, path: path }
  fetch(uri, { method: method, headers: { Authorization: `Bearer ${getCookie(ACCESS_TOKEN_COOOKIE_NAME)}` } })
    .then(response => handleResponse(response).json())
    .then(data => processResponseData({ ...state, data: data }))
    .catch(err => processResponseData({ ...state, data: err.message }))
}

const openUrl = (url, target = '_self') => window.open(url, target)

const login = (url) => openUrl(url)

const account = (url) => openUrl(url, '_blank')

const logout = (url) => {
  document.cookie = `${ACCESS_TOKEN_COOOKIE_NAME}=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/`
  openUrl(url, '_blank')
  openUrl('index.html')
}

const send = (e) => {
  e.preventDefault()
  const { uri, method, title, path } = e.target.dataset
  const userOperation = userOperations.find(operation => operation.method.name === method)
  if (userOperation) {
    userOperation.method(uri)
  } else {
    sendApiRequest(uri, method, title, path)
  }

  Array.from(document.getElementsByClassName('menu-link')).forEach(el => el.classList.remove('active'))
  e.target.classList.add('active')
}

const createMenuItem = (menu, operation) => {
  const { id, label, method, baseUrl, apiPath } = operation
  const uri = apiPath ? baseUrl + apiPath : baseUrl

  a = document.createElement('a')
  a.setAttribute('id', id)
  a.setAttribute('data-uri', uri)
  a.setAttribute('data-method', typeof method == "function" ? method.name : method)
  a.setAttribute('data-title', label)
  a.setAttribute('data-path', apiPath)
  a.setAttribute('href', baseUrl)
  a.classList.add('menu-link')
  a.innerHTML = label
  a.onclick = send
  li = document.createElement('li')
  li.append(a)
  document.getElementById(menu).append(li)
}

const loadPage = () => {
  const { readersUiEndpoint, newsApiEndpoint, keycloakRealm } = document.body.dataset

  userOperations = [
    { id: 'user-login',   label: 'Login',   method: login,   baseUrl: `${keycloakRealm}/protocol/openid-connect/auth?client_id=readers-ui&redirect_uri=${readersUiEndpoint}/auth&scope=openid&response_type=code` },
    { id: 'user-account', label: 'Account', method: account, baseUrl: `${keycloakRealm}/account` },
    { id: 'user-logout',  label: 'Logout',  method: logout,  baseUrl: `${keycloakRealm}/protocol/openid-connect/logout` },
  ]

  const appOperations = [
    { id: 'app-economy', label: 'Economy', method: 'GET', baseUrl: newsApiEndpoint, apiPath: '/economy' },
    { id: 'app-society', label: 'Society', method: 'GET', baseUrl: newsApiEndpoint, apiPath: '/society' },
    { id: 'app-sports',  label: 'Sports',  method: 'GET', baseUrl: newsApiEndpoint, apiPath: '/sports' },
    { id: 'app-tech',    label: 'Tech',    method: 'GET', baseUrl: newsApiEndpoint, apiPath: '/tech' },
  ]

  // create menu items
  userOperations.forEach(operation => createMenuItem('user-menu', operation))
  appOperations.forEach(operation => createMenuItem('app-menu', operation))

  // load from path
  const path = window.location.pathname
  const operation = appOperations.find(operation => operation.apiPath === path)
  if (operation) {
    document.getElementById(operation.id).click()
  }
}

loadPage()
