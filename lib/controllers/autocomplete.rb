
require('aurita')
Aurita.import_module :gui, :autocomplete_result
Aurita.import_plugin_model :wiki, :article
Aurita.import_plugin_model :wiki, :media_asset

module Aurita
module Plugins
module Wiki

  class Autocomplete_Controller < Plugin_Controller

    def all_articles
      key_attrib = param(:field)
      key   = param(key_attrib.to_sym) if key_attrib
      key ||= param(:article)
      return unless key
			return unless Aurita.user.category_ids.length > 0
			tags = key.split(' ')
      num_results   = param(:num_results)
      num_results ||= 10

			tag  = "%#{tags.join(' ')}%"
      
      articles       = Article.find(num_results).with((Article.has_tag(tags) | 
                                              Article.title.ilike(tag)))
      articles.sort_by(Wiki::Article.article_id, :desc)

      article_result = HTML.ul.autocomplete { } 
      
      key = tags.join(' ')
      pkey_attrib   = param(:pkey)
      pkey_attrib ||= :article_id
      articles.each { |a|
        pkey = a.__send__(pkey_attrib)
        article_result << HTML.li.autocomplete(:id => pkey) { a.title } 
      }
      return article_result
    end

    def find_articles(params={})
			tags   = params[:keys]
      tags ||= params[:key]
      return unless tags
			return unless Aurita.user.readable_category_ids.length > 0
			tag  = "%#{tags.join(' ')}%"

      articles       = Article.find(10).with((Article.has_tag(tags) | 
                                              Article.title.ilike(tag)) & 
                                             Article.is_accessible)
      articles.sort_by(Wiki::Article.article_id, :desc)

      article_result = Aurita::GUI::Autocomplete_Result.new()
      
      key = tags.join(' ')
      articles.each { |a|
        tags  = a.tags.gsub(key, %{<b>#{key}</b>})
        title = a.title.gsub(key, %{<b>#{key}</b>}).gsub(key.capitalize, %{<b>#{key.capitalize}</b>})
        article_result.entries << { :class => :autocomplete_article, 
                                    :id => "Wiki__Article__#{a.article_id}", 
                                    :header => tl(:articles), 
                                    :title => title, 
                                    :informal => tags }
      }
      return article_result
    end
    
    def find_media(params={})
      return unless params[:keys]
			return unless Aurita.user.category_ids.length > 0
			tags = params[:keys]
			tag  = "%#{tags[-1]}%"
      
			constraints  = Wiki::Media_Asset.deleted == 'f'
      media        = Media_Asset.find(10).with(constraints & 
                                               ((Media_Asset.title.ilike("%#{tags.join(' ')}%") | 
                                                 Media_Asset.has_tag(tags)) & 
                                                Media_Asset.accessible)
                                              ).sort_by(Media_Asset.media_asset_id, :desc).entities
      media_result = Aurita::GUI::Autocomplete_Result.new()
      
      info  = ''
      exten = ''
      media.each { |m|
        
        thumbnail_string = ''
        inline_image     = ''
        thumb_path = m.fs_path(:size => :tiny)

=begin
# Nice idea, but IE does not support base64 encoded, inline images. 

        if File.exists?(thumb_path) then
          File.open(thumb_path, "r") { |t|
            thumbnail_string = t.read
          }
          inline_image = Base64.encode64(thumbnail_string)
          "<img src=\"data:image/jpg;base64, \n#{inline_image}\" />"
        end
=end

        exten = m.media_asset_id
        exten = m.mime_extension unless m.has_preview? 
        info = ''
        info = '<b>' << m.title.to_s << '</b><br />' 
        info << m.tags.to_s 
        entry = '<div style="height: 70px; width: 70px; text-align: center; background-color: #cccccc; float: left; ">' << m.icon(:tiny) + '</div>
                 <div style="float: left; color: #555555; margin-left: 4px; width: 320px; overflow: hidden; ">' << info.to_s +  '</div>'

        media_result.entries << { :class   => :autocomplete_image, 
                                  :id      => "Wiki__Media_Asset__#{m.media_asset_id}", 
                                  :element => entry, 
                                  :header  => tl(:media) }
      }
      return media_result
    end

  end

end
end
end

