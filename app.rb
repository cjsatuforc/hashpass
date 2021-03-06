require 'bundler'
require 'sinatra'
require 'webrick/https'
require 'sinatra/json'
require 'sinatra/namespace'
require 'sinatra/base'
require 'sinatra/reloader'
require 'sinatra/custom_logger'
require 'logger'
require 'sequel'
require 'sqlite3'
require 'json'
require 'logger'
require 'pry'
require 'mail'
require 'listen'
require 'dotenv/load'
require 'bcrypt'
require 'openssl'
require 'jwt'
require 'rack/attack'
require 'active_support/time'
require 'active_support/cache'
require_relative 'src/server/notifications'
require_relative 'src/server/log_parser.rb'
require_relative 'src/server/api.rb'

##
# Connect to SQLite
DB = Sequel.connect('sqlite://hashpass.db')
DB[:active].delete

##
# Hash model
class Hashes < Sequel::Model(DB[:hashes])
end

##
# Attack History model
class History < Sequel::Model(DB[:history])
end

##
# Dictionary model
class Dics < Sequel::Model(DB[:dictionaries])
end

##
# Rules model
class Rules < Sequel::Model(DB[:rules])
end

##
# RottenPi model
class Rotten < Sequel::Model(DB[:rotten])
end


##
# User model
class User < Sequel::Model
  include BCrypt

  def password
    @password ||= Password.new(password_hash)
  end

  def password=(new_password)
    @password = Password.create(new_password)
    self.password_hash = @password
  end
end

class Rack::Attack
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new 
  if ENV['APP_ENV'] == 'development'
    Rack::Attack.safelist("localhost") { |req| req.ip == "127.0.0.1" }
  end
  
  # Block too many login attempts
  throttle('hplogin', limit: 90, period: 90.seconds) do |req|
    if req.path == '/hplogin' && req.post?
      req.ip
    end
  end

  # Block too many requests
  throttle('req/ip', limit: 137, period: 5.minutes) do |req|
    ignore = ['status','running','pending','cracked', 'heartbeat', 'getcmd', 'command', 'agent']
    unless ignore.any? { |i| req.path.include?(i) }
      req.ip
    end
  end  
end

##
# Public (user not authorized)
class Public < Sinatra::Base
  helpers Sinatra::CustomLogger
  set :environment, :production if ENV['APP_ENV'] == 'production'

  configure :development, :production do
    logger = Logger.new(File.open("#{root}/logs/#{environment}.log", 'a'))
    logger.level = Logger::DEBUG if development?
    set :logger, logger
  end

  def initialize
    super
  end

  not_found do
    File.read(File.join('public', 'app.html'))
  end

  def ip(request)
    "[#{ request.env['REMOTE_ADDR'] }] --> "
  end


  get '/wpa/:ssid' do
    response.headers['Cache-Control'] = 'public, max-age=1'
    exists = DB[:hashes].where(name: params['ssid']).first

    if exists
      ssid = params['ssid']
      password = DB[:hashes].where(name: params['ssid']).get(:loot)
      if password
        password = password.delete("\n").rstrip 
      else 
        return [201, {}, ['']]
      end
      conf = <<~HEREDOC        
        update_config=1
        network={
                ssid="#{ ssid }"
                psk="#{ password }"
        }
      HEREDOC
      File.write("wpa/#{ ssid }_wpa_supplicant.conf", conf)
      send_file("./wpa/#{ ssid }_wpa_supplicant.conf", 
        :filename => ".wpa/#{ ssid }_wpa_supplicant.conf", 
        :type => 'Application/octet-stream'
      )
    else
      [201, {}, ['']]
    end
  end

  # get '/agent/attackplan' do
  #   plan = [
  #     # {
  #     #   actions: ['pmkid', 'shutdown:60']
  #     # },
  #     {
  #       ssid: "The Darkside",
  #       actions: ['recon']
  #     },
  #     # {
  #     #   ssid: 'Bird1',
  #     #   actions: ['recon', 'shutdown']
  #     # }
  #     # ssid: ["Luna Secret Rlouter"],
  #     # ssid: ["Luna's Wooffi"]
  #   ].to_json
  # end


  post '/agent-upload' do
    puts "Agent Upload! #{request.body}"
    logger.info "#{ request.inspect } Agent uploading files: #{ params[:files] }."
    # verify_scope request, 'create' do |req, username|      
      api = API.new
      puts "params: #{ params }"
      p api.agent_upload(params[:files], params[:ssid])
      json success: true
    # end
  end

  get '/agent/logs/:ssid' do
    response.headers['Cache-Control'] = 'public, max-age=1'
    begin      
      json Dir["agent/#{ params['ssid'] }/log/*"].map! { |f| f.split('/').last }
    rescue
      [201, {}, ['']]
      next
    end
  end

  get '/agent/log/:ssid/:log' do
    begin
      File.read("agent/#{ params['ssid'] }/log/#{ params['log'] }")
    rescue
      [201, {}, ['']]
      next
    end
  end

  get '/agent/ssh' do
    `/root/hashpass/src/server/oterm.sh /root/hashpass/src/server/autos.sh`
    [200, {}, ['']]
  end

  get '/' do
    logger.info "#{ request.inspect } get / ."
    File.read(File.join('public', 'app.html'))
  end

  post '/hplogin' do
    request.body.rewind
    params = JSON.parse(request.body.read)
    @user = User.first(email: params['handle'])
    
    if @user.nil? || params['handle'].empty?
      logger.warn "#{ ip(request) } User #{params['handle']} doesn't exist."
      halt 401     
    elsif params['handle'].empty?
      logger.warn "#{ ip(request) } User didn't supply username."
      halt 401 
    elsif @user.password == params['password']
      logger.info "++ #{ ip(request) } User #{params['handle']} (#{@user.role}) logged in."
      hmac_secret = ENV['SECRET']
      scope = 
        if @user.role == 'admin'
          ['create', 'read', 'update', 'delete', 'user_management', 'loot']
        else
          ['create', 'read', 'update', 'loot']
        end
      payload = {
        exp: Time.now.to_i + 60 * 60 * 24,
        iat: Time.now.to_i,
        iss: ENV['JWT_ISSUER'],
        scopes: scope,
        user: {
          username: @user.email
        }
      }
      token = JWT.encode(payload, hmac_secret, 'HS256')
      decoded_token = JWT.decode token, hmac_secret, true, { algorithm: 'HS256' }

      { token: token }.to_json
    else
      logger.warn "#{ request.inspect } Wrong password for #{@user.email} (#{ params['password'] })."
      halt 401
    end
  end
end

##
# JSON Web Tokens
class JwtAuth
  def initialize app
    @app = app
  end

  def call env
    begin
      options = { algorithm: 'HS256', iss: ENV['JWT_ISSUER'] }
      bearer = env.fetch('HTTP_AUTHORIZATION', '').slice(7..-1)
      payload, header = JWT.decode bearer, ENV['SECRET'], true, options

      env[:scopes] = payload['scopes']
      env[:user] = payload['user']

      @app.call env
    rescue JWT::DecodeError
      [ 401, { 'Content-Type' => 'text/html' }, [File.read(File.join('public', 'app.html'))] ]
    rescue JWT::ExpiredSignature
      [ 403, { 'Content-Type' => 'text/html' }, [File.read(File.join('public', 'app.html'))] ]
    rescue JWT::InvalidIssuerError
      [ 403, { 'Content-Type' => 'text/html' }, [File.read(File.join('public', 'app.html'))] ]
    rescue JWT::InvalidIatError
      [ 403, { 'Content-Type' => 'text/html' }, [File.read(File.join('public', 'app.html'))] ]
    end
  end

end

##
# API
class Api < Sinatra::Base
  use JwtAuth
  register Sinatra::Namespace
  helpers Sinatra::CustomLogger  
  api = API.new
  notifications = Notifications.new  
  set :environment, :production if ENV['APP_ENV'] == 'production'  

  configure :development do
    register Sinatra::Reloader
  end

  configure :development, :production do
    logger = Logger.new(File.open("#{root}/logs/#{environment}.log", 'a'))
    logger.level = Logger::DEBUG if development?
    set :logger, logger
  end

  def initialize
    super
  end

  def ip(request)
    "[#{ request.env['REMOTE_ADDR'] }] --> "
  end

  def verify_scope req, scope
    scopes, user = req.env.values_at :scopes, :user
    username = user['username'].to_sym if user['username']

    if scopes.include?(scope)
      yield req, username
    else
      halt 403
    end
  end


  not_found do
    api.main_page
  end

  # Agent updates
  ['checkin', 'checkout', 'heartbeat', 'command'].each do |endpoint|
    post "/agent/#{ endpoint }" do      
      verify_scope request, 'update' do |req, username|
        request.body.rewind
        param = JSON.parse(request.body.read)
        DB[:rotten].insert(
          user: request.env[:user]['username'],
          event: endpoint.upcase,
          result: param['result'],
          function: param['function'],
          arguments: param['arguments'],
          timestamp: Time.now.to_s
        )
        [200, {}, ['']]
      end
    end
  end

  post '/agent/newcommand' do
    puts "params: #{params}"
    verify_scope request, 'create' do |req, username|
      request.body.rewind
      param = JSON.parse(request.body.read)
      puts "param: #{param}"
      DB[:rotten_cmd].insert(
        user: param['user'],
        function: param['function'],
        arguments: param['arguments'],
        timestamp: Time.now.to_s
      )
      [200, {}, ['']]
    end
  end

  get '/agent/commands' do
    verify_scope request, 'read' do |req, username|
      status 204 if DB[:rotten_cmd].all.empty?
      json DB[:rotten_cmd].all
    end
  end

  get '/agent/:user/getcmd' do
    cmd = DB[:rotten_cmd].where(user: params['user']).all
    DB[:rotten_cmd].where(user: params['user']).delete
    json cmd
  end

  delete '/agent/rotten/command/:id' do
    verify_scope request, 'delete' do |req, username|
      deleted = DB[:rotten_cmd].where(id: params['id']).delete
      json deleted: deleted if deleted
    end
  end

  delete '/agent/rotten/commands' do
    verify_scope request, 'delete' do |req, username|
      deleted = DB[:rotten_cmd].delete
      [200, {}, ['']] if deleted
    end
  end



  get '/agent/rotten' do
    verify_scope request, 'read' do |req, username|
      status 204 if DB[:rotten].all.empty?
      json DB[:rotten].all
    end
  end

  delete '/agent/rotten' do
    verify_scope request, 'delete' do |req, username|
      deleted = DB[:rotten].delete
      [200, {}, ['']] if deleted
    end
  end



  get '/start' do
    verify_scope request, 'update' do |req, username|
      logger.info "#{ ip(request) } Starting attack."
      pending = DB[:pending].first
      active = DB[:active].first
      if active.nil? && pending
        api.promote
        json pid: api.start(active)
      end
      json pid: api.start(active)
    end
  end

  get '/stop/:id' do
    verify_scope request, 'update' do |req, username|
      logger.info "#{ ip(request) } Stopping attack."
      api.stop
      json killed: true
    end
  end

  post '/upload' do
    puts "Upload! #{request}"
    logger.info "#{ request.inspect } Uploading files: #{ params[:files] }."
    verify_scope request, 'create' do |req, username|      
      p api.upload(params[:files])
      json success: true
    end
  end


  get '/status' do
    verify_scope request, 'read' do |req, username|
      if DB[:active].first
        active = DB[:active].first
        json api.status(active)
      else
        status 204
      end
    end
  end

  get '/dics' do
    verify_scope request, 'read' do |req, username|
      status 204 if DB[:dictionaries].all.empty?
      json DB[:dictionaries].reverse_order(:size).all
    end
  end

  post '/dic' do
    verify_scope request, 'create' do |req, username|
      logger.info "#{ ip(request) } Created dictionary #{ params['name'] }."
      request.body.rewind
      json api.insert_dic(JSON.parse(request.body.read))
    end
  end

  delete '/dic/:id' do
    verify_scope request, 'delete' do |req, username|
      deleted = Dics.where(id: params['id']).delete
      json deleted: deleted if deleted
    end
  end


  get '/rules' do
    verify_scope request, 'read' do |req, username|
      status 204 if DB[:rules].all.empty?
      json DB[:rules].all
    end
  end

  post '/rule' do
    verify_scope request, 'create' do |req, username|
      logger.info "#{ ip(request) } Created rule #{ params['name'] }."
      request.body.rewind
      json api.insert_rule(JSON.parse(request.body.read)).values
    end
  end

  delete '/rule/:id' do
    verify_scope request, 'delete' do |req, username|
      logger.info "#{ ip(request) } Created rule #{ params['id'] }."
      deleted = Rules.where(id: params['id']).delete
      json deleted: deleted if deleted
    end
  end


  get '/users' do
    verify_scope request, 'user_management' do |req, username|
      status 204 if DB[:users].all.empty?
      json DB[:users].all
    end
  end

  post '/user' do
    verify_scope request, 'user_management' do |req, username|
      request.body.rewind
      param = JSON.parse(request.body.read)
      logger.warn "!! #{ ip(request) } Created User #{ param['name'] } !!"      
      @new_user = 
        User.new(
          email: param['name'], 
          password: param['password'], 
          role: param['role'])
      json @new_user.save
    end
  end

  delete '/user/:id' do
    verify_scope request, 'user_management' do |req, username|
      logger.warn "!! #{ ip(request) } #{username} deleted user #{ params['id'] } !!"
      deleted = User.where(id: params['id']).delete
      json deleted: deleted if deleted
    end
  end


  get '/hashes' do
    verify_scope request, 'read' do |req, username|
      status 204 if DB[:hashes].all.empty?
      json DB[:hashes].reverse_order(:added).all
    end
  end

  get '/history' do
    verify_scope request, 'read' do |req, username|
      status 204 if DB[:history].all.empty?
      json DB[:history].reverse_order(:started_on).all
    end
  end

  get '/history/:id' do
    verify_scope request, 'read' do |req, username|
      history = 
        DB[:history]
          .where(hashid: params['id'])
          .reverse_order(:started_on)
          .all
      json history ? history : 'not found'
    end
  end

  delete '/hashes/:id' do
    verify_scope request, 'delete' do |req, username|
      logger.warn "#{ ip(request) } Deleted hash #{ params['id'] }."
      deleted = Hashes.where(id: params['id']).delete
      json deleted: deleted if deleted
    end
  end

  post '/hashes/insert' do
    verify_scope request, 'create' do |req, username|
      logger.info "#{ ip(request) } Created Hash #{ params['name'] }."
      request.body.rewind
      api.insert_hash(JSON.parse(request.body.read))
    end
  end

  namespace '/running' do
    get do
      verify_scope request, 'read' do |req, username|
        status 204 if DB[:active].all.empty?
        json running: DB[:active].all
      end
    end

    delete do
      verify_scope request, 'delete' do |req, username|
        logger.info "#{ ip(request) } Deleted running."
        json success: true if DB[:active].delete
      end
    end

    get '/promote' do
      verify_scope request, 'update' do |req, username|
        json success: api.promote
      end
    end
  end

  namespace '/pending' do
    get do
      verify_scope request, 'read' do |req, username|
        json pending: DB[:pending].all
      end
    end

    delete do
      verify_scope request, 'delete' do |req, username|
        logger.info "#{ ip(request) } Deleted queue."
        DB[:pending].delete
        json success: true
      end
    end

    post do
      verify_scope request, 'create' do |req, username|
        logger.info "#{ ip(request) } Added to queue."
        request.body.rewind
        json success: true if api.new(JSON.parse(request.body.read))
      end
    end
  end

  namespace '/cracked' do
    get do
      verify_scope request, 'loot' do |req, username|
        status 204 if DB[:cracked].all.empty?
        json cracked: DB[:cracked].all
      end
    end

    delete do
      verify_scope request, 'delete' do |req, username|
        logger.info "#{ ip(request) } Slingn crack."
        json success: true if DB[:cracked].delete
      end
    end

    get '/:id' do
      verify_scope request, 'loot' do |req, username|
        json cracked: DB[:cracked].where(id: params['id']).first
      end
    end
  end
end
