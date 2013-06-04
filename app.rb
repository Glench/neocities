require './environment.rb'

use Rack::Session::Cookie, key:          'neocities',
                           path:         '/',
                           expire_after: 31556926, # one year in seconds
                           secret:       $config['session_secret']

get %r{.+} do
  pass if request.host == '127.0.0.1'
  subname = request.host.match /[\w-]+/
  pass if subname.nil?
  subname = subname.to_s
  pass if subname == 'www' || subname == 'neocities' || subname == 'testneocities'

  base_path = site_base_path subname
  path = File.join(base_path, (request.path =~ /\/$/ ? (request.path + 'index.html') : request.path))

  cache_control :public, max_age: 10

  if File.exist?(path)
    send_file path
  else
    send_file File.join(base_path, 'not_found.html')
  end

  send_file path
end

get '/?' do
  dashboard_if_signed_in
  slim :index
end

get '/new' do
  dashboard_if_signed_in
  @site = Site.new
  slim :'new'
end

get '/dashboard' do
  slim :'dashboard'
end

get '/signin' do
  dashboard_if_signed_in
  slim :'signin'
end

post '/create' do
  dashboard_if_signed_in
  @site = Site.new username: params[:username], password: params[:password], email: params[:email], new_tags: params[:tags]

  if @site.valid?
    
    base_path = site_base_path @site.username

    DB.transaction {
      @site.save

      begin
        FileUtils.mkdir base_path
      rescue Errno::EEXIST
      end

      File.write File.join(base_path, 'index.html'), slim(:'templates/index', pretty: true, layout: false)
      File.write File.join(base_path, 'not_found.html'), slim(:'templates/not_found', pretty: true, layout: false)
    }

    session[:id] = @site.id
    redirect '/dashboard'
  else
    slim :'/new'
  end
end

post '/signin' do
  dashboard_if_signed_in
  if Site.valid_login? params[:username], params[:password]
    site = Site[username: params[:username]]
    session[:id] = site.id
    redirect '/dashboard'
  else
    flash[:error] = 'Invalid login.'
    redirect '/signin'
  end
end

get '/signout' do
  require_login
  session[:id] = nil
  redirect '/'
end

# Helper routes to get webalizer stats working, not used by anything important
get '/sites/:name/?' do  
 sites_name_redirect
end

get '/sites/:name/:file' do
  sites_name_redirect
end

get '/site_files/new' do
  require_login
  slim :'site_files/new'
end

post '/site_files/upload' do
  require_login
  @errors = []
  
  if params[:newfile] == '' || params[:newfile].nil?
    @errors << 'You must select a file to upload.'
    halt slim(:'site_files/new')
  end
  
  if params[:newfile][:tempfile].size > Site::MAX_SPACE || (params[:newfile][:tempfile].size + current_site.total_space) > Site::MAX_SPACE
    @errors << 'File size must be smaller than available space.'
    halt slim(:'site_files/new')
  end
  
  mime_type = Magic.guess_file_mime_type params[:newfile][:tempfile].path
  
  unless Site::VALID_MIME_TYPES.include?(mime_type) && Site::VALID_EXTENSIONS.include?(File.extname(params[:newfile][:filename]).sub(/^./, ''))
    @errors << 'File must me one of the following: HTML, Text, Image (JPG PNG GIF JPEG SVG), JS, CSS, Markdown.'
    halt slim(:'site_files/new')
  end

  sanitized_filename = params[:newfile][:filename].gsub(/[^a-zA-Z_\-.]/, '')

  FileUtils.mv params[:newfile][:tempfile].path, File.join(site_base_path(current_site.username), sanitized_filename)
  flash[:success] = "Successfully uploaded file #{sanitized_filename}."
  redirect '/dashboard'
end

post '/site_files/delete' do
  require_login
  sanitized_filename = params[:filename].gsub(/[^a-zA-Z_\-.]/, '')
  FileUtils.rm File.join(site_base_path(current_site.username), sanitized_filename)
  flash[:success] = "Deleted file #{params[:filename]}."
  redirect '/dashboard'
end

get '/terms' do
  slim :'terms'
end

get '/privacy' do
  slim :'privacy'
end

def sites_name_redirect
  path = request.path.gsub "/sites/#{params[:name]}", ''
  # path += "/#{params[:file]}" unless params[:file].nil?

  redirect "http://#{params[:name]}.neocities.org#{path}"
end

def dashboard_if_signed_in
  redirect '/dashboard' if signed_in?
end

def require_login
  redirect '/' unless signed_in?
end

def signed_in?
  !session[:id].nil?
end

def current_site
  @site ||= Site[id: session[:id]]
end

def site_base_path(subname)
  File.join settings.public_folder, 'sites', subname
end

def template_site_title(username)
  "#{username.capitalize}#{username[username.length-1] == 's' ? "'" : "'s"} Site"
end
