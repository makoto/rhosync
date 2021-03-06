require 'digest/md5'
require 'yaml'
require 'open-uri'
require 'net/http'
require 'net/https'

class SourcesController < ApplicationController

  before_filter :login_required, :except => :clientcreate
  
  include SourcesHelper
  # shows all object values in XML structure given a supplied source
  # if a :last_update parameter is supplied then only show data that has been
  # refreshed (retrieved from the backend) since then
  protect_from_forgery :only => [:create, :delete, :update]

  # ONLY SUBSCRIBERS MAY ACCESS THIS!
  def show
    @source=Source.find params[:id]
    @app=@source.app
    check_access(@app)
    @source.refresh(@current_user) if @source.needs_refresh
    # if client_id is provided, return only relevant object for that client
    if params[:client_id] and params[:id]
      @object_values=process_objects_for_client(@source, params[:client_id]) 
    else
      @object_values=ObjectValue.find :all,:conditions=>{:update_type=>"query",:source_id=>params[:id]},:order=>"object"
    end
    @object_values.delete_if {|o| o.value.nil? || o.value.size<1 }  # don't send back blank or nil OAV triples
    logger.info "Sending #{@object_values.length} records to #{params[:client_id]}" if params[:client_id] and @object_values
    respond_to do |format|
      format.html
      format.xml  { render :xml => @object_values}
      format.json
    end
  end
  
  # this is effectively the "callback" or notify function that needs to be called from the backend app
  # this is installed by the "set_callback" method that should be written for source adapters when appropriate
  def refresh
    @source=Source.find params[:id]
    @source.refresh(@current_user) if @source
  end

  # return the metadata for the specified source
  # ONLY FOR SUBSCRIBERS/ADMIN
  def attributes
    @source=Source.find params[:id]
    check_access(@source.app)
    # get the distinct list of attributes that is available
    @attributes=ObjectValue.find_by_sql "select distinct(attrib) from object_values where source_id="+params[:id]

    respond_to do |format|
      format.html
      format.xml  { render :xml => @attributes}
      format.json { render :json => @attributes}
    end
  end
  
  # generate a new client for this source
  def clientcreate
    @client = Client.new
    
    respond_to do |format|
      if @client.save
        format.json { render :json => @client }
        format.xml  { head :ok }
      end
    end
  end


  # this creates all of the rows in the object values table corresponding to
  # the array of hashes given by the attrvals parameter
  # note that the REFRESH action below will later DELETE all of the created records
  #
  # also note YOU MUST CREATE A TEMPORARY OBJECT ID. Some form of hash or CRC
  #  of all of the values can be used
  #
  # for example
  # :attrvals=
  #   [{"object"=>"temp1","attrib"=>"name","value"=>"rhomobile"},
  #   {"object"=>"temp1","attrib"=>"industry","value"=>"software"},
  #   {"object"=>"temp1","attrib"=>"employees","value"=>"500"}
  #   {"object"=>"temp2","attrib"=>"name","value"=>"mobio"},
  #   {"object"=>"temp2","attrib"=>"industry","value"=>"software"},
  #   {"object"=>"temp3","attrib"=>"name","value"=>"xaware"},
  #   {"object"=>"temp3","attrib"=>"industry","value"=>"software"}]
  #
  # RETURNS:
  #   a hash of the object_values table ID columns as keys and the updated_at times as values
  def createobjects
    @source=Source.find params[:id]
    check_access(@source.app)
    objects={}
    @client = Client.find_by_client_id(params[:client_id]) if params[:client_id]
    params[:attrvals].each do |x| # for each hash in the array
       # note that there should NOT be an object value for new records
       o=ObjectValue.new
       o.object=x["object"]
       o.attrib=x["attrib"]
       o.value=x["value"]
       o.update_type="create"
       o.source=@source
       o.user_id=current_user.id
       o.save
       # add the created ID + created_at time to the list
       objects[o.id]=o.created_at if not objects.keys.index(o.id)  # add to list of objects
    end

    respond_to do |format|
      format.html { 
        flash[:notice]="Created objects"
        redirect_to :action=>"show",:id=>@source.id,:app_id=>@source.app.id
      }
      format.xml  { render :xml => objects }
      format.json  { render :json => objects }
    end
  end

  # this creates all of the rows in the object values table corresponding to
  # the array of hashes given by the attrval parameter.
  # note that the REFRESH action below will later DELETE all of the created records
  #  # for example
  # :attrvals=
  #   [{"object"=>"1","attrib"=>"name","value"=>"rhomobile"},
  #   {"object"=>"1","attrib"=>"industry","value"=>"software"},
  #   {"object"=>"1","attrib"=>"employees","value
  #   {"object"=>"2","attrib"=>"name","value"=>"mobio"},
  #   {"object"=>"2","attrib"=>"industry","value"=>"software"},
  #   {"object"=>"3","attrib"=>"name","value"=>"xaware"},
  #   {"object"=>"3","attrib"=>"industry","value"=>"software"}]
  #
  # RETURNS:
  #   a hash of the object_values table ID columns as keys and the updated_at times as values
  def updateobjects
    @source=Source.find params[:id]
    check_access(@source.app)
    objects={}
    params[:attrvals].each do |x|  # for each hash in the array
       o=ObjectValue.new
       o.object=x["object"]
       o.attrib=x["attrib"]
       o.value=x["value"]
       o.update_type="update"
       o.user_id=current_user.id
       o.source=@source
       o.save
       # add the created ID + created_at time to the list
       objects[o.id]=o.created_at if not objects.keys.index(o.id)  # add to list of objects
    end

    respond_to do |format|
      format.html { 
        flash[:notice]="Updated objects"
        redirect_to :action=>"show",:id=>@source.id,:app_id=>@source.app.id
      }
      format.xml  { render :xml => objects }
      format.json  { render :json => objects }
    end
  end

  # this creates all of the rows in the object values table corresponding to
  # the hash given by attrvals.
  # note that the REFRESH action below will later DELETE all of the created records
  #
  # RETURNS:
  #   a hash of the object_values table ID columns as keys and the updated_at times as values
  def deleteobjects
    @source=Source.find params[:id]
    check_access(@source.app)
    objects={}
    params[:attrvals].each do |x|
       o=ObjectValue.new
       o.object=x["object"]
       o.attrib=x["attrib"] if x["attrib"]
       o.value=x["value"] if x["value"]
       o.update_type="delete"
       o.source=@source
       o.user_id=current_user.id
       o.save
       # add the created ID + created_at time to the list
       objects[o.id]=o.created_at if not objects.keys.index(o.id)  # add to list of objects
    end

    respond_to do |format|
      format.html do
            flash[:notice]="Deleted objects"
            redirect_to :action=>"show"
      end
      format.xml  { render :xml => objects }
      format.json { render :json => objects }
    end
  end

  def editobject
    # bring up an editing form for
    @object=ObjectValue.find_by_source_id_and_object_and_attrib params[:id],params[:object],params[:attrib]
  end

  def newobject
    @source=Source.find params[:id]
  end


  def pick_load
    # go to the view to pick the file to load
  end

  def load_all
    # NOTE: THIS DOES NOT WORK FROM OUR SAVING FORMAT RIGHT NOW! (the one that save_all does)
    # it only works from the YAML format in db/migrate/sources.yml
    # this is a very well reported upon Ruby/YAML issue
    @sources=YAML::load_file params[:yaml_file]
    p @sources
    @sources.keys.each do |x|
      source=Source.new(@sources[x])
      source.save
    end
    flash[:notice]="Loaded sources"
    redirect_to :action=>"index"
  end

  def pick_save
    # go to the view to pick the file
    @app=App.find params[:app_id] if params[:app_id]
  end

  def save_all
    if params[:app_id].nil?
      @app=App.find_by_admin request.headers['login']
    else
      @app=App.find params[:app_id] 
      @sources=@app.sources if @app
    end
    File.open(params[:yaml_file],'w') do |out|
      @sources.each do |x|
        YAML.dump(x,out)
      end
    end
    flash[:notice]="Saved sources"
    redirect_to :action=>"index"
  end


  # this connects to the web service of the given source backend and:
  # - does a login
  # - does creating, updating, deleting of records as required
  # - reads (queries) records from the backend
  # - logs off
  #
  # It should be invoked on a schedcurrent_useruled basis by some admin process,
  # for example by using CURL.  It should also be done with a separate instance
  # than the one used to service create, update and delete calls from the client
  # device.
  def refresh
    source=Source.find params[:id]
    check_access(source.app)
    source.refresh @current_user
    redirect_to :action=>"show",:id=>source.id, :app_id=>source.app.id
  end
  
  # GET /sources
  # GET /sources.xml
  # this returns all sources that are associated with a given "app" as determine by the token
  def index    
    login=current_user.login.downcase
    if params[:app_id].nil?
      @app=App.find_by_admin login
    else
      @app=App.find params[:app_id] 
    end
    @sources=@app.sources if @app
        
    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @sources }
    end
  end

  # GET /sources/new
  # GET /sources/new.xml
  def new
    @source = Source.new
    @source.app=App.find params[:app] if params[:app]
    @apps=App.find_all_by_admin(current_user.login)
    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @source }
    end
  end

  # GET /sources/1/edit
  def edit
    if current_user.nil?
      redirect_to :controller=>:sessions,:action=>:new 
    else
      p "Current user: " + current_user.login
    end
    @source = Source.find(params[:id])
    @app=@source.app
    @apps=App.find_all_by_admin(current_user.login) 
    render :action=>"edit"
  end

  # POST /sources
  # POST /sources.xml
  def create
    @source = Source.new(params[:source])
    @app=App.find params["source"]["app_id"]
    
    respond_to do |format|
      if @source.save
        flash[:notice] = 'Source was successfully created.'
        format.html { redirect_to(:controller=>"apps",:action=>:edit,:id=>@app.id) }
        format.xml  { render :xml => @source, :status => :created, :location => @source }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @source.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /sources/1
  # PUT /sources/1.xml
  def update
    @source = Source.find(params[:id])
    @app=App.find params["source"]["app_id"]

    respond_to do |format|
      begin
        if @source.update_attributes(params[:source])
          flash[:notice] = 'Source was successfully updated.'
          format.html { redirect_to(:controller=>"apps",:action=>:edit,:id=>@app.id) }
          format.xml  { head :ok }
        else
          begin  # call underlying save! so we can get some exceptions back to report
            # (update_attributes just calls save
            @source.save!
          rescue Exception
            flash[:notice] = $!
          end

          format.html { render :action => "edit" }
          format.xml  { render :xml => @source.errors, :status => :unprocessable_entity }
        end
      end
    end

  end

  # DELETE /sources/1
  # DELETE /sources/1.xml
  def destroy
    @source=Source.find(params[:id])
    @source.destroy
    @app=App.find params[:app_id]
    respond_to do |format|
      format.html { redirect_to :controller=>"apps",:action=>"edit",:id=>@app.id }
      format.xml  { head :ok }
    end
  end

end
