# frozen_string_literal: true

class TextFormatter
  include ActionView::Helpers::TextHelper
  include ERB::Util
  include RoutingHelper

  URL_PREFIX_REGEX = %r{\A(https?://(www\.)?|xmpp:)}

  DEFAULT_REL = %w(nofollow noopener).freeze

  DEFAULT_OPTIONS = {
    multiline: true,
  }.freeze

  attr_reader :text, :options

  # @param [String] text
  # @param [Hash] options
  # @option options [Boolean] :multiline
  # @option options [Boolean] :with_domains
  # @option options [Boolean] :with_rel_me
  # @option options [Array<Account>] :preloaded_accounts
  def initialize(text, options = {})
    @text    = text
    @options = DEFAULT_OPTIONS.merge(options)
  end

  def entities
    @entities ||= Extractor.extract_entities_with_indices(text, extract_url_without_protocol: false)
  end

  def to_s
    return ''.html_safe if text.blank?

    html = nil
    MastodonOTELTracer.in_span('TextFormatter#to_s extract_and_rewrite') do
      html = rewrite do |entity|
        if entity[:url]
          link_to_url(entity)
        elsif entity[:hashtag]
          link_to_hashtag(entity)
        elsif entity[:screen_name]
          link_to_mention(entity)
        end
      end
    end

    # 멘션/해시태그/링크 처리 후에 마크다운 적용
    html = apply_simple_markdown(html)

    if multiline?
      MastodonOTELTracer.in_span('TextFormatter#to_s simple_format') do
        html = simple_format(html, {}, sanitize: false).delete("\n")
      end
    end

    html = html.gsub(/\u200C(<blockquote>.*?<\/blockquote>|<hr>|<tablee>.*?<\/tablee>|<tabled>.*?<\/tabled>|<tablec>.*?<\/tablec>|<tableb>.*?<\/tableb>|<tablea>.*?<\/tablea>|<tablef>.*?<\/tablef>|<ectf>.*?<\/ectf>|<ecte>.*?<\/ecte>|<ectd>.*?<\/ectd>|<ectc>.*?<\/ectc>|<ectb>.*?<\/ectb>|<ecta>.*?<\/ecta>)\u200C/m, '\1')
    #html = html.gsub(/\u200C(<blockquote>.*?<\/blockquote>|<hr>|<tablee>.*?<\/tablee>|<tabled>.*?<\/tabled>|<tablec>.*?<\/tablec>|<tableb>.*?<\/tableb>|<tablea>.*?<\/tablea>)\u200C/m, '\1')
    #html = html.gsub(/\u200C(<blockquote>.*?<\/blockquote>|<hr>)\u200C/m, '\1')
    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  class << self
    include ERB::Util
    include ActionView::Helpers::TagHelper

    def shortened_link(url, rel_me: false)
      url = Addressable::URI.parse(url).to_s
      rel = rel_me ? (DEFAULT_REL + %w(me)) : DEFAULT_REL

      prefix      = url.match(URL_PREFIX_REGEX).to_s
      display_url = url[prefix.length, 30]
      suffix      = url[prefix.length + 30..]
      cutoff      = url[prefix.length..].length > 30

      if suffix && suffix.length == 1 # revert truncation to account for ellipsis
        display_url += suffix
        suffix = nil
        cutoff = false
      end

      tag.a href: url, target: '_blank', rel: rel.join(' '), translate: 'no' do
        tag.span(prefix, class: 'invisible') +
          tag.span(display_url, class: (cutoff ? 'ellipsis' : '')) +
          tag.span(suffix, class: 'invisible')
      end
    rescue Addressable::URI::InvalidURIError, IDN::Idna::IdnaError
      h(url)
    end
  end

  private

  def apply_simple_markdown(html)

    html = html.gsub(/\{([^\}]+)\]\<([^>]+)\>/, '<a href="\2">\1</a>')
    
    # 수평선
    html = html.gsub(/\n?-{3,}\s*\n/, "\u200C<hr>\u200C")

    # *****ai*****
    html = html.gsub(/\*\*\*\*\*([^\*\n<>]+)\*\*\*\*\*/, '<ty>\1</ty>')

    # ****ai****
    html = html.gsub(/\*\*\*\*([^\*\n<>]+)\*\*\*\*/, '<ai>\1</ai>')

    # ***굵은 기울임***
    html = html.gsub(/\*\*\*([^\*\n<>]+)\*\*\*/, '<poem>\1</poem>')

    # **굵게**
    html = html.gsub(/\*\*([^\*\n<>]+)\*\*/, '<strong>\1</strong>')

    # *기울임*
    html = html.gsub(/(?<!\*)\*([^\*\n<>]+)\*(?!\*)/, '<em>\1</em>')

    # __밑줄__
    html = html.gsub(/__([^_\n<>]+)__/, '<u>\1</u>')

    # $인용$
    #html = html.gsub(/(\n?)$([^$\n<>]+)$(\n?)/, "\u200C<blockquote>\\2</blockquote>\u200C")

    # 1. 테이블f 
    html = html.gsub(/(\n?)\`\`\`\`\`\`([^\`\n<>]+)\`\`\`\`\`\`(\n?)/, "\u200C<tablef>\\2</tablef>\u200C")

    # 1. 테이블e (가장 긴 마커: `````)
    html = html.gsub(/(\n?)\`\`\`\`\`([^\`\n<>]+)\`\`\`\`\`(\n?)/, "\u200C<tablee>\\2</tablee>\u200C")

    # 2. 테이블d (````)
    html = html.gsub(/(\n?)\`\`\`\`([^\`\n<>]+)\`\`\`\`(\n?)/,  "\u200C<tabled>\\2</tabled>\u200C")

    # 3. 테이블c (```)
    html = html.gsub(/(\n?)\`\`\`([^\`\n<>]+)\`\`\`(\n?)/,  "\u200C<tablec>\\2</tablec>\u200C")

    # 3. 테이블b (``)
    html = html.gsub(/(\n?)\`\`([^\`\n<>]+)\`\`(\n?)/,  "\u200C<tableb>\\2</tableb>\u200C")

    # 5. 테이블a (가장 짧은 마커: `)
    html = html.gsub(/(\n?)(?<!\`)\`([^\`\n<>]+)\`(?!\`)(\n?)/,  "\u200C<tablea>\\2</tablea>\u200C")

    # 0. 기타e $$$$$$
    html = html.gsub(/(\n?)\$\$\$\$\$\$([^\$\n<>]+)\$\$\$\$\$\$(\n?)/, "\u200C<ectf>\\2</ectf>\u200C")

    # 1. 기타e $$$$$
    html = html.gsub(/(\n?)\$\$\$\$\$([^\$\n<>]+)\$\$\$\$\$(\n?)/, "\u200C<ecte>\\2</ecte>\u200C")

    # 2. 기타d $$$$
    html = html.gsub(/(\n?)\$\$\$\$([^\$\n<>]+)\$\$\$\$(\n?)/,  "\u200C<ectd>\\2</ectd>\u200C")

    # 3. 기타c $$$
    html = html.gsub(/(\n?)\$\$\$([^\$\n<>]+)\$\$\$(\n?)/,  "\u200C<ectc>\\2</ectc>\u200C")

    # 3. 기타b $$
    html = html.gsub(/(\n?)\$\$([^\$\n<>]+)\$\$(\n?)/,  "\u200C<ectb>\\2</ectb>\u200C")

    # 5. 기타a $
    html = html.gsub(/(\n?)(?<!\$)\$([^\$\n<>]+)\$(?!\$)(\n?)/,  "\u200C<ecta>\\2</ecta>\u200C")



    # hair space 강조
    html = html.gsub(/\u200A([^\u200A\n<>]+)\u200A/, '<span style="color: #1d9bf0;">\1</span>')

    html
  end

  def rewrite
    entities.sort_by! do |entity|
      entity[:indices].first
    end

    result = +''

    last_index = entities.reduce(0) do |index, entity|
      indices = entity[:indices]
      result << h(text[index...indices.first])
      result << yield(entity)
      indices.last
    end

    result << h(text[last_index..])

    result
  end

  def link_to_url(entity)
    MastodonOTELTracer.in_span('TextFormatter#link_to_url') do
      TextFormatter.shortened_link(entity[:url], rel_me: with_rel_me?)
    end
  end

  def link_to_hashtag(entity)
    MastodonOTELTracer.in_span('TextFormatter#link_to_hashtag') do
      hashtag = entity[:hashtag]
      url     = tag_url(hashtag)

      <<~HTML.squish
        <a href="#{h(url)}" class="mention hashtag" rel="tag">#<span>#{h(hashtag)}</span></a>
      HTML
    end
  end

  def link_to_mention(entity)
    MastodonOTELTracer.in_span('TextFormatter#link_to_mention') do
      username, domain = entity[:screen_name].split('@')
      domain           = nil if local_domain?(domain)
      account          = nil

      if preloaded_accounts?
        same_username_hits = 0

        preloaded_accounts.each do |other_account|
          same_username = other_account.username.casecmp(username).zero?
          same_domain   = other_account.domain.nil? ? domain.nil? : other_account.domain.casecmp(domain)&.zero?

          if same_username && !same_domain
            same_username_hits += 1
          elsif same_username && same_domain
            account = other_account
          end
        end
      else
        account = entity_cache.mention(username, domain)
      end

      return "@#{h(entity[:screen_name])}" if account.nil?

      url = ActivityPub::TagManager.instance.url_for(account)
      display_username = same_username_hits&.positive? || with_domains? ? account.pretty_acct : account.username

      <<~HTML.squish
        <span class="h-card" translate="no"><a href="#{h(url)}" class="u-url mention">@<span>#{h(display_username)}</span></a></span>
      HTML
    end
  end

  def entity_cache
    @entity_cache ||= EntityCache.instance
  end

  def tag_manager
    @tag_manager ||= TagManager.instance
  end

  delegate :local_domain?, to: :tag_manager

  def multiline?
    options[:multiline]
  end

  def with_domains?
    options[:with_domains]
  end

  def with_rel_me?
    options[:with_rel_me]
  end

  def preloaded_accounts
    options[:preloaded_accounts]
  end

  def preloaded_accounts?
    preloaded_accounts.present?
  end
end