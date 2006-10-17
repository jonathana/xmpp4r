# =XMPP4R - XMPP Library for Ruby                                                                                     
# License:: Ruby's license (see the LICENSE file) or GNU GPL, at your option.                                         
# Website::http://home.gna.org/xmpp4r/ 

require 'xmpp4r/pubsub/iq/pubsub'
require 'xmpp4r/dataforms'

module Jabber
  module PubSub
    ##
    # A Helper for a PubSub Service

    class ServiceHelper

      ##
      # new(client,pubsubjid)
      # client:: [Jabber::Stream]
      # pubsubjid:: [String] or [Jabber::JID]
      # creates a new "connection" to a pubsub service
      def initialize(client,pubsubjid)
        @client = client
        @pubsubjid = pubsubjid
	@event_cbs = CallbackList.new
	@client.add_message_callback(200,self) { |message|
	  handle_message(message)
	}
      end

      ##
      # create(jid,node,configure)
      # node:: [String] you node name - otherwise you get a automaticly generated one (in most cases)
      # configure:: [Jabber::XMLStanza] if you want to configure you node (default nil)
      # creates a new node on the pubsub service
      # returns [String]
      def create(node=nil,configure=nil)
        rnode = nil
        iq = basic_pubsub_query(:set)
        iq.pubsub.add(REXML::Element.new('create')).attributes['node'] = node
        if configure
          confele =  REXML::Element.new('configure')

          if configure.type_of?(XMLStanza)
            confele << configure
          end
          iq.pubsub.add(confele)
        end

        @client.send_with_id(iq) { |reply|
          if (create = reply.first_element('pubsub/create'))
            rnode = create.attributes['node']
          end
          true
        }

        rnode
      end

      ##
      # delete(node)
      # node:: [String]
      # deletes a pubsub node
      # returns true
      def delete(node)
        iq = basic_pubsub_query(:set)
        iq.pubsub.add(REXML::Element.new('delete')).attributes['node'] = node

        @client.send_with_id(iq) { |reply|
          true
        }
      end

      ##
      # publish(node,item)
      # node:: [String]
      # item:: [Jabber::PubSub::Item]
      # NOTE: this method sends only one item per publish request because some services may not
      # allow batch processing
      # maybe this will changed in the future
      # returns true 
      def publish(node,item)
        iq = basic_pubsub_query(:set)
        publish = iq.pubsub.add(REXML::Element.new('publish'))
        publish.attributes['node'] = node
	if item.kind_of?(Jabber::PubSub::Item)
	  publish.add(item)
	  p iq.to_s
          @client.send_with_id(iq) { |reply| true }
	end
      end

      ##
      # publish_with_id(node,xmlitem,id)
      # node:: [String]
      # item:: [REXML::Element]
      # id:: [String]
      # retrun true
      def publish_with_id(node,item,id)
	if item.kind_of?(REXML::Element)
	  xmlitem = Jabber::PubSub::Item.new
	  xmlitem.id = id
	  xmlitem.add(item)
	  publish(node,xmlitem)
	else 
	  raise "given item is not a proper xml document or Jabber::PubSub::Item"
	end
      end

      ##
      # items(node)
      # node:: [String]
      # count:: [Fixnum]
      # gets all items from a pubsub node
      # returns [Hash] { id => [Jabber::PubSub::Item]}
      def items(node,count=nil)
        iq = basic_pubsub_query(:get)
        items = Jabber::PubSub::Items.new
        items.node = node
        iq.pubsub.add(items)

        res = nil
        @client.send_with_id(iq) { |reply|
        # i don't know why testing the reply of Iq and Pubsub stanzas
        # but stephan probably knows ;)
          if reply.kind_of?(Iq) and reply.pubsub and reply.pubsub.first_element('items')
            res = {}
            reply.pubsub.first_element('items').each_element('item') do |item|
              p item.to_s
              res[item.attributes['id']] = item.children.first if item.children.first
            end
          end
          true
        }
        res
      end

      ##
      # affiliations
      # showes the affiliations on a pubsub service
      # returns a [Hash] of { node => symbol }
      def affiliations
        iq = basic_pubsub_query(:get)
        iq.pubsub.add(REXML::Element.new('affiliations'))
        res = nil
        @client.send_with_id(iq) { |reply|
          if reply.pubsub.first_element('affiliations')
            res = {}
            reply.pubsub.first_element('affiliations').each_element('affiliation') do |affiliation|
              # TODO: This should be handled by an affiliation element class
              aff = case affiliation.attributes['affiliation']
                      when 'owner' then :owner
                      when 'publisher' then :publisher
                      when 'none' then :none
                      when 'outcast' then :outcast
                      else nil
                    end
              res[affiliation.attributes['node']] = aff
            end
    	  end
          true
        }
        res
      end

      ##
      # get_all_subscriptions
      # showes all subscriptions on a pubsub service
      # returns an [Array] of [REXML::Element]
      def get_all_subscriptions
        subscriptions(nil)
      end

      ##
      # subscriptions(node)
      # node:: [String] or nil
      # showes all subscriptions on the given node
      # returns an [Array] of [REXML::Element]
      def subscriptions(node)
        iq = basic_pubsub_query(:get)
        entities = iq.pubsub.add(REXML::Element.new('subscriptions'))
        entities.attributes['node'] = node

        res = nil
        @client.send_with_id(iq) { |reply|
          if reply.pubsub.first_element('subscriptions')
            res = []
            reply.pubsub.first_element('subscriptions').each_element('subscription') { |subscription|
              res << REXML::Element.new(subscription)
            }
          end
          true
        }
        res
      end

      ##
      # subscribers(node)
      # node:: [String]
      # showes all jids of subscribers of a node
      # gives back a [Array] of [String]

      def subscribers(node)
        res = []
        subscriptions(node).each { |sub|
          res << sub.attributes['jid']
        }
        res
      end

      ##
      # subscribe(node)
      # node:: [String]
      # subscribe to a node
      # returns [Hash] of { attributename => value }
      def subscribe(node)
        iq = basic_pubsub_query(:set)
        sub = REXML::Element.new('subscribe')
        sub.attributes['node'] = node
        sub.attributes['jid'] = @client.jid.strip
        iq.pubsub.add(sub)
        repl = {}
        @client.send_with_id(iq) do |reply|
          pubsubanswer = reply.pubsub
          if pubsubanswer.first_element('subscription')
            pubsubanswer.each_element('subscription') { |element|
              element.attributes.each { |name,value| repl.store(name,value) }
            }
          end
          true
        end # @client.send_with_id(iq)
        repl
      end

      ##
      # unsubscribe(node,subid)
      # node:: [String]
      # subid:: [String] or nil
      # return true
      def unsubscribe(node,subid=nil)
        iq = basic_pubsub_query(:set)
        unsub = REXML::Element.new('unsubscribe')
        unsub.attributes['node'] = node
        unsub.attributes['jid'] = @client.jid.strip
        unsub.attributes['subid'] = subid
        iq.pubsub.add(unsub)
        @client.send_with_id(iq) { |reply| true	} # @client.send_with_id(iq)
      end

      ##
      # get_options(node,subid=nil)
      # node:: [String]
      # subid:: [String] or nil
      # return [Jabber::XData]
      def get_options(node,subid=nil)
        iq = basic_pubsub_query(:get)
        opt = REXML::Element.new('options')
        opt.attributes['node'] = node
        opt.attributes['jid'] = @client.jid.strip
        opt.attributes['subid'] = subid
        iq.pubsub.add(opt)
        ret = nil
        @client.send_with_id(iq) { |reply|
          reply.pubsub.options.first_element('x') { |xdata|
            ret = xdata if xdata.kind_of?(Jabber::XData)
          }
        true
        }
      end

      ##
      # get_options(node,options,subid=nil)
      # node:: [String]
      # options:: [Jabber::XData]
      # subid:: [String] or nil
      # returns true
      def set_options(node,options,subid=nil)
        iq = basic_pubsub_query(:set)
        opt = REXML::Element.new('options')
        opt.attributes['node'] = node
        opt.attributes['jid'] = @client.jid.strip
        opt.attributes['subid'] = subid
        iq.pubsub.add(opt)
        iq.pubsub.options.add(options)
        @client.send_with_id(iq) { |reply| true }
      end
      
      # returns [String]
      def to_s
        @pubsubjid.to_s
      end
      
      ##
      # add_event_callback
      # returns
      def add_event_callback(prio = 200, ref = nil, &block)
        @event_cbs.add(prio, ref, block)
      end

      private


      def basic_pubsub_query(type)
        iq = Jabber::Iq::new(type,@pubsubjid)
        iq.add(IqPubSub.new)
        iq
      end
      
      ##
      # vor handling the incoming events
      def handle_message(message)
	if message.from == @pubsubjid and message.first_element('event')
	  event = message.first_element('event')
	  @event_cbs.process(event)
	end
      end
      
    end
  end
end