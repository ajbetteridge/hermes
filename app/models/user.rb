class User < ActiveRecord::Base
  has_many :conversations
  has_many :friends, :through => :conversations, :source => :to_users
  
  validates_uniqueness_of :uid, :allow_blank => true
  
  validates_presence_of :handle, :unless => :email?
  validates_presence_of :email, :unless => :handle?
  
  before_create :create_access_token
  
  class << self
    # Find or new user by Twiter oauth information
    def authorize_twitter!(auth)
      return unless auth && auth.uid
    
      user = self.find_by_uid(auth.uid) || self.new
      user.link_twitter!(auth)
      user
    end
    
    # Find or new user by handle or email address
    def for(to_users)
      UserExtractor.extract(to_users)
    end
    
    def from_handle(handle)
      find_or_create_by_handle(handle)
    end
    
    def from_mail(mail)
      if mail.domain.downcase == Rails.config.domain
        return find_or_create_by_handle(mail.local)
      end
      
      address     = mail.address.downcase
      user        = find_by_email(address) || self.new(:email => address)
      user.name ||= mail.name
      user.save!
      user
    end
  end
  
  def link_twitter!(auth)
    self.uid            = auth.uid
    self.handle         = auth.info.nickname
    self.name           = auth.info.name
    self.description    = auth.info.description
    self.avatar_url     = auth.info.image
    self.twitter_token  = auth.credentials.token
    self.twitter_secret = auth.credentials.secret
    save!
  end
  
  def link_google!(auth)
    self.email         = auth.info.email
    self.google_token  = auth.credentials.token
    save!
  end
  
  def app_email
    [handle, "@", Rails.config.domain].join('')
  end
  
  def to_s
    handle? ? "@#{handle}" : email
  end
  
  def to_name
    name || to_s
  end
  
  def to_name_s
    name? ? "#{name.inspect} <#{to_s}>" : to_s
  end
  
  def google
    Google::Client.new(self.google_token)
  end
  
  def google?
    google_token?
  end
  
  def twitter
    Twitter::Client.new(
      oauth_token:        self.twitter_token,
      oauth_token_secret: self.twitter_secret
    )
  end
  
  def twitter?
    twitter_token?
  end  
  
  alias_method :member?, :twitter?
  
  def autocomplete
    friends_autocomplete | twitter_autocomplete | google_autocomplete
  end
  
  def avatar_url
    avatar_url = read_attribute(:avatar_url)
    if avatar_url.blank?
      avatar_url = Gravatar.make(email) if email? 
      avatar_url ||= Gravatar.robohash(to_s)
    end
    avatar_url
  end
  
  def serializable_hash(options = {})
    super(options.merge(
      :except => [
        :twitter_token, :twitter_secret, 
        :google_token, :access_token, :uid
      ]
    ))
  end
  
  protected
    def twitter_autocomplete
      return [] unless twitter? 
      Rails.cache.fetch([cache_key, :autocomplete, :twitter].join('/')) do
        friend_ids = twitter.friend_ids.ids.shuffle[0..99]
        friends    = twitter.users(*friend_ids)
        friends.map {|f| "#{f.name.inspect} @#{f.screen_name}" }
      end
    end
    
    def google_autocomplete
      return [] unless google?
      Rails.cache.fetch([cache_key, :autocomplete, :google].join('/')) do
        google.contacts.select(&:email).map(&:to_s)
      end
    end

    def friends_autocomplete
      friends.map(&:to_name_s)
    end
    
    def create_access_token
      self.access_token = SecureRandom.hex(16)
    end
end