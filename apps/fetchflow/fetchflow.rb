<<notes

1. Finding a client in fetchflow before adding a new one requires R&D, 
   Fetchflow has shitty API, they are returning clients even after 
   deleting all clients from their web interface. 
2. Clients are not unique! Same email address can be added multiple times if we 
   let them manage the client-id. @supportbee - if you guys have a unique key 
   per contact/client/new_user_in_ticket, please use that in requests. 
notes

module Fetchflow
  module EventHandler
    def ticket_created
      begin
        ticket    = payload.ticket
        requester = ticket.requester 
        return [200, 'Client creation disabled'] unless settings.should_create_client.to_s == '1'
        client = create_new_client(requester)
        html   = new_client_info_html(client)
      rescue Exception => e
        puts "#{e.message}\n#{e.backtrace}"
        [500, e.message]
      end

      create_in_fetchflow(client) if client
      comment_on_ticket(ticket, html)
      [200, "Client added to fetchflow"]
    end
  end
end

module Fetchflow
  class Base < SupportBeeApp::Base
    string   :api_token, :required => true, :label => 'API Token', :hint => 'Your fetchflow API token available under "API" menu in fetchflow.'
    password :password, :required => true
    boolean  :should_create_client, :default => true, :label => 'Add new supportbee client as fetchflow clients'

    white_list :should_create_client
    
    private 

    def create_new_client(requester)
      client =  create_client(requester)
    end
    
    def create_client(requester)
      return unless settings.should_create_client.to_s == '1'
      firstname = split_name(requester).first
      lastname  = split_name(requester).last

      client = Fetchflow_client.new(
                 :firstname => firstname,
                 :lastname  => lastname,
                 :email     => requester.email
               )
    end
    
    def split_name(requester)
      requester.name ? requester.name.split(' ') : [requester.email,'']
    end
    
    def new_client_info_html(client)
      html = ""
      html << "Added #{client.firstname} #{client.lastname} to Fetchflow... "
      html
    end
    
    def comment_on_ticket(ticket, html)
      ticket.comment(:html => html)
    end


    # Ideally this method should be in Fetchflow_Client class below and should be called 
    # using something like "client.save()"
    # Since I am lazy to findout how to send your http_post through that class, I am 
    # leaving it here! 
    def create_in_fetchflow(client)
      begin
        response = http_post "https://www.fetchflow.com/API/XMLRequest/" do |req|
          req.headers['Content-Type'] = "application/xml"
          req.body = %Q(<?xml version="1.0" encoding="utf-8" ?>
 <Request authtoken="#{settings.api_token}" password="#{settings.password}">
   <Action type="client" method="create">
     <ContactName>#{client.firstname} #{client.lastname}</ContactName>
     <Email>#{client.email}</Email>
   </Action>
 </Request>)
        end
      rescue Exception => e
        puts "#{e.message}\n#{e.backtrace}"
        return [500, e.message]
      end

      if response.status == 200 and response.body
        response_xml = Nokogiri::XML(response.body).xpath("//*[@status]")
        status = response_xml[0].attr('status')
        unless status == 'success'
          puts status
          return [500, status]
        end
      else
        msg = "Something went wrong while adding fetchflow client"
        puts msg
        return [500, msg]
      end
    end
  end

  class Fetchflow_client 
    attr_accessor :firstname, :lastname, :email

    def initialize(options = {})
      self.firstname = options[:firstname] || ''
      self.lastname  = options[:lastname] || ''
      self.email     = options[:email] || ''
    end
  end
end

