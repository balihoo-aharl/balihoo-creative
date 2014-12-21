
fs        = require 'fs'
qs        = require 'querystring'
opn       = require 'opn'
sse       = (require 'sse-stream')('/updates')
path      = require 'path'
http      = require 'http'
mime      = require 'mime'
colors    = require 'colors'
chokidar  = require 'chokidar'
mustache  = require 'mustache'
parseURL  = (require 'url').parse

console.log "Balihoo Web Designer Toolkit".blue

# argv = require('minimist') process.argv.slice(2)

# Project level configuration file
configPath = './assets/.balihoo-creative.json'

ignoreFile = (path) ->
  /^\./.test(path) || /\/\./.test(path) || /~$/.test(path)

# Load in the static HTML that is the console
consoleContent = fs.readFileSync __dirname + '/../console.html'

# Return an object representation the files in the assets/ dir
scanAssetsDir = ->
  partials = {}
  validFiles = {}
  base = process.cwd() + "/assets"
  walk = (cdir) ->
    dir = {}
    for fileName in fs.readdirSync cdir
      assetPath = "#{cdir}/#{fileName}"
      if not ignoreFile assetPath
        stat = fs.statSync assetPath
        if stat.isDirectory()
          # Asset directory key is directory name
          dir[fileName] = walk assetPath
        else
          # Asset's key is file name without extension
          key = fileName.replace /\.[^/.]+$/, ''
          ext = (fileName.substr key.length + 1).toLowerCase()
          val = assetPath.substr base.length
          if ext is 'mustache'
            partials[key] = fs.readFileSync(assetPath, encoding:'utf8')
          else
            validFiles["./assets#{val}"] = fs.readFileSync assetPath
            dir[key] = "/_#{val}"
    dir
  assets = walk base
  [assets, partials, validFiles]

# If there is no assets directory, then we should build one
if not fs.existsSync './assets/'
  console.log 'Creating an assets/ directory'.yellow
  needAssets = true
  fs.mkdirSync './assets/'

# If this is a brand new project then go ahead and set it up
if not fs.existsSync configPath
  # By default, use the current working directory as the project name
  projectName = path.basename process.cwd()
  console.log "Setting up new project: #{projectName.green}".yellow
  config =
    name: projectName
    description: ''
    pages: ['index']
    template: 'main'
else
  console.log "Found existing project config file #{configPath.gray}"
  config = JSON.parse fs.readFileSync configPath, encoding:'utf8'

# If the asset directory doesn't already exist, then create one
if needAssets
  # Recursively copy files from srcDir to destDir
  rcopy = (srcDir, destDir, indent) ->
    for fileName in fs.readdirSync srcDir
      srcPath = "#{srcDir}/#{fileName}"
      destPath = "#{destDir}/#{fileName}"

      stat = fs.statSync srcPath
      if stat.isDirectory()
        console.log "#{indent}#{fileName}/".white
        fs.mkdirSync destPath unless fs.existsSync destPath
        rcopy srcPath, destPath, indent + '  ' 
      else if not fileName.match /\.swp$/
        console.log "#{indent}  #{fileName}".white
        fs.writeFileSync(destPath, fs.readFileSync(srcPath))

  # Recursively copy all the template files into the current project 
  console.log "Creating a project skeleton in #{__dirname}/../template".yellow
  rcopy __dirname + '/../template', process.cwd(), '  '


# Start with an up to date view of the assets directory
[config.assets, partials, validFiles] = scanAssetsDir()
if not config.template? then config.template = 'main'
if not config.pages then config.pages = [config.template]
fs.writeFileSync configPath, JSON.stringify(config, null, "  ")

parseRequest = (url) ->
  parts = parseURL url

  # Start with the parsed querystring
  result = qs.parse parts.query
  result.path = parts.pathname

  # Get all of the parts of the path with empty parts removed
  path = (part.toLowerCase() for part in parts.pathname.split /\// when part.length > 0)

  # The page is the directory of the path or 'index'
  result.page = if path.length > 0 then path.shift() else 'index'
  result.ifpage = {}
  result.ifpage[result.page] = true

  # The remaining directory parts are key/value pairs
  # If an odd number remain, the last key's has value is undefined
  for p in [0...path.length] by 2
    result[path[p]] = {}
    if path.length > p + 1
      result[path[p]][path[p+1]] = true
    else
      result[path[p]] = undefined
  result

server = http.createServer (req, res) ->
  context =
    request: parseRequest req.url
    assets: config.assets
  # Load the console that uses SSE to reload the iframed pages
  if context.request.ifpage.$console?
    res.writeHead 200, 'Content-Type': 'text/html'
    res.end consoleContent
  # Serve up the static content
  else if context.request.ifpage._?
    assetFile = './assets' + context.request.path.substring 2
    if validFiles.hasOwnProperty assetFile
      res.writeHead 200, 'Content-Type': mime.lookup assetFile
      res.end validFiles[assetFile]
    else
      res.writeHead 404, 'Content-Type': 'text/html'
      if partials.hasOwnProperty '404'
        res.end(mustache.render partials['404'], context, partials)
      else
        res.end 'Page Not Found'
  # Server up the templated content
  else
    if context.request.page not in config.pages
      res.writeHead 404, 'Content-Type': 'text/html'
      if partials.hasOwnProperty '404'
        res.end(mustache.render partials['404'], context, partials)
      else
        res.end 'Page Not Found'
    else
      res.writeHead 200, 'Content-Type': 'text/html'
      res.end(mustache.render partials[config.template], context, partials)

clients = []
sse.install server
sse.on 'connection', (client) ->
  clients.push client
  client.write '/'

  client.on 'end', ->
    clients.splice clients.indexOf(client), 1

port = 8088
server.listen port

console.log "Opening console in web browser".inverse
opn "http://localhost:#{port}/$console"

# Watch the assets directory and see if any files change, add or delete
# We don't really care what happens to the directory, we'll just recompute all
chokidar.watch( './assets/', ignoreInitial: yes).on 'all', (event, path)->
  if /\.balihoo-creative\.json$/.test path
    console.log "#{path} has been updated, reloading".red.inverse
    config = JSON.parse fs.readFileSync configPath, encoding:'utf8'
    saveConfig = false
  else if ignoreFile path || not /^assets\//.test path
    return
  else
    console.log "#{event} detected in #{path}".yellow

  [config.assets, partials, validFiles] = scanAssetsDir()
  if not config.template? then config.template = 'main'
  if not config.pages then config.pages = [config.template]
  client.write 'refresh' for client in clients
  if saveConfig
    console.log "Updating config file".green
    fs.writeFileSync configPath, JSON.stringify(config, null, "  ")

