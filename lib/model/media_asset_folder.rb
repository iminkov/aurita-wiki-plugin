
require('aurita/model')
Aurita::Main.import_model :content
Aurita.import_module :access_strategy
Aurita.import_plugin_model :wiki, :asset
Aurita.import_plugin_model :wiki, :strategies, :category_based_folder_access
Aurita.import_plugin_model :wiki, :media_asset_folder_category

module Aurita
module Plugins
module Wiki

  class Media_Asset_Folder < Aurita::Model
  include Access_Strategy

    table :media_asset_folder, :public
    primary_key :media_asset_folder_id, :media_asset_folder_id_seq

    use_label :physical_path

    expects :physical_path

    use_access_strategy(Category_Based_Folder_Access, 
                        :managed_by => Media_Asset_Folder_Category, 
                        :mapping    => { :media_asset_folder_id => :category_id })

    def access_strategy
      @access_strategy ||= self.class.access_strategy.new(self)
      @access_strategy
    end

    def label
      physical_path
    end

    def icon
      Aurita::GUI::HTML.img(:class => :media_asset_folder_icon, :src => '/aurita/images/icons/folder_thumb.gif')
    end

    def folder_path
      asset_folder_id = media_folder_id__parent
      return [] if asset_folder_id.to_s == ''
      path = []
      folder = Media_Asset_Folder.find(1).with(Media_Asset_Folder.media_asset_folder_id == asset_folder_id).entity 
      if folder then
        path += folder.folder_path
      end
      path << self
      path 
    end

    def is_user_folder(user=nil)
      if user then
        (access == 'PRIVATE' && 
         user_group_id == Aurita.user.user_group_id &&
         media_folder_id__parent == 100)
      else
        access == 'PRIVATE'
      end
    end
    alias is_user_folder_of is_user_folder
    alias is_user_folder? is_user_folder
    alias is_home_dir? is_user_folder
    alias is_home_dir_of? is_user_folder

    # Returns sizes of all Media_Assets contained in this directory, 
    # ordered by file size, as pair of [ media_asset_id, filesize ]
    # Example
    #
    #   dir = Media_Asset_Folder.get(300)
    #   dir.file_sizes 
    #
    #   --> 
    #
    #   # Assuming there are two Media_Assets in this directory, with 
    #   # file sizes 1 and 2 Mib: 
    #
    #   [ ['123', '1024'], ['343, '2048'] ]
    #
    def file_sizes(filter_params={})
      return @file_sizes if @file_sizes

      @file_sizes   = {}
      folder_params = {}
      clause = (Media_Asset.media_folder_id == media_asset_folder_id) 
      if !filter_params[:filter] then
        clause = clause & (Media_Asset.is_accessible)
      elsif filter_params[:filter].is_a?(Lore::Clause) then
        clause = clause & filter_params[:filter]
        folder_params = { :filter => :none }
      end
      Media_Asset.select_values(:media_asset_id, :filesize) { |ma|
        ma.where(clause)
        ma.order_by(:filesize, :asc)
      }.each { |pair| 
        @file_sizes[pair.at(0).to_i] = pair.at(1).to_i
      }
      media_asset_folders(folder_params).each { |f|
        @file_sizes.update(f.file_sizes(filter_params))
      }
      return @file_sizes
    end

    def num_files(filter_params={})
      return @num_files if @num_files
      @num_files = file_sizes(filter_params).length
      return @num_files
    end

    def total_size()
      file_sizes.values.sum
    end

    def self.media_assets_of(folder_id, params={})
      sort     = params[:sort]
      sort_dir = params[:sort_dir].to_sym if params[:sort_dir]
      assets   = Media_Asset.all_with((Media_Asset.media_folder_id == folder_id) & 
                                      (Media_Asset.deleted == 'f') & 
                                      (Media_Asset.accessible))
      assets.sort_by(sort, sort_dir)
      assets.entities
    end
    def media_assets(params={})
      @media_asset_entries = self.class.media_assets_of(media_asset_folder_id, params) unless @media_asset_entries
      @media_asset_entries
    end

    def self.media_asset_folders_of(folder_id, params={})
      return [] unless folder_id

      sort       = params[:sort]
      sort_dir   = params[:sort_dir]
      sort     ||= :physical_path
      sort_dir ||= :asc

      clause     = ((Media_Asset_Folder.trashbin == 'f') & 
                    (Media_Asset_Folder.media_folder_id__parent == folder_id))
      if params[:filter] != :none then
        clause = clause & (Media_Asset_Folder.accessible) 
      end
      folders = Media_Asset_Folder.all_with(clause)
      folders.sort_by(sort, sort_dir.to_sym)
      entries = folders.entities
      entries
    end
    def media_asset_folders(params={})
      @media_asset_folder_entries = self.class.media_asset_folders_of(media_asset_folder_id, params) unless @media_asset_folder_entries
      @media_asset_folder_entries
    end
    
    def parent_id
      media_folder_id__parent
    end
    def self.children_of(folder_id)
      media_asset_folders_of(folder_id)
    end
    def parent_node
      Media_Asset_Folder.load(:media_asset_folder_id => media_folder_id__parent)
    end
    alias parent_folder parent_node
    def child_nodes
      self.class.children_of(media_asset_folder_id)
    end
    alias child_folders child_nodes
    alias subfolders child_nodes
    alias folders child_nodes

    def has_subfolders? 
      !Media_Asset_Folder.find(1).with(Media_Asset_Folder.accessible & 
          (Media_Asset_Folder.media_folder_id__parent == media_asset_folder_id)).entity.nil?
    end

    def is_child_of?(folder)
      folder_id = folder.media_asset_folder_id if folder.is_a?(Aurita::Model)
      folder_id = folder
      # Every folder is child of root level
      return true if (folder_id.to_s == '0')
      # Folder is immediate child 
      return true if (media_folder_id__parent == folder_id) 
      
      parent = parent_node()
      while(parent && parent.media_asset_folder_id != 0) do
        return true if parent.media_asset_folder_id == folder_id
        parent = parent.parent_node
      end
      return false
    end

    def is_user_folder?
      is_child_of?(100)
    end

    def self.hierarchy_level(params={})
      filter      = params[:filter]
      parent_id   = params[:parent_id]
      indent      = params[:indent]
      indent    ||= 0
      parent_id ||= 0
      hierarchy = []
      constraints = (Media_Asset_Folder.accessible) 
      constraints = (constraints & (Media_Asset_Folder.trashbin == 'f'))
      constraints = (constraints & (Media_Asset_Folder.media_folder_id__parent == parent_id)) 
      constraints = (constraints & filter) if filter
      if params[:exclude_folder_ids] && params[:exclude_folder_ids].length > 0 then
        constraints = (constraints & 
                       (Media_Asset_Folder.media_asset_folder_id.not_in(params[:exclude_folder_ids])))
      end
      Media_Asset_Folder.all_with(constraints).sort_by(:physical_path, :asc).each { |folder| 
        hierarchy << { :folder => folder, :indent => indent }
      }
      return hierarchy
    end

    def self.hierarchy(params={})
      current_indent     = params[:indent]
      current_indent   ||= 0
      params[:indent]    = 0 unless params[:indent]
      params[:parent_id] = 0 unless params[:parent_id]
      level = hierarchy_level(params)
      list  = level
      level.each { |entry| 
        params[:parent_id] = entry[:folder].media_asset_folder_id
        params[:indent]    = current_indent+1
        list += hierarchy(params)
      }
      return list
    end

    def self.private_folders(params={})
      hierarchy(:filter => (Media_Asset_Folder.user_group_id == Aurita.user.user_group_id),
                :parent_id => 0) +
      hierarchy(:filter => (Media_Asset_Folder.user_group_id == Aurita.user.user_group_id)) 
    end
    def self.private_folders_root
      hierarchy_level(:filter => (Media_Asset_Folder.user_group_id == Aurita.user.user_group_id))
    end

    def self.public_folders(params={})
      if Aurita.user.is_admin? then 
        return hierarchy(:filter => (Media_Asset_Folder.user_group_id <=> Aurita.user.user_group_id),
                         :exclude_folder_ids => params[:exclude_folder_ids])
      else
        return hierarchy(:filter => (:user_group_id <=> Aurita.user.user_group_id))
      end
    end
    def self.public_folders_root
      if Aurita.user.is_admin? then 
        return hierarchy_level(:filter => (Media_Asset_Folder.user_group_id <=> Aurita.user.user_group_id))
      else
        return hierarchy_level(:filter => (Media_Asset_Folder.access == 'PUBLIC'))
      end
    end

  end 

end # module
end # module

module Main

  class User_Group < Aurita::Model

    def may_view_folder?(folder)
      folder.access_strategy.permits_read_access_for(self)
    end
    alias may_view_folder may_view_folder? 

    # Folder may be edited if user is admin or folder has 
    # been created by user himself. 
    def may_edit_folder?(folder)
      folder.access_strategy.permits_edit_for(self)
    end

    def may_write_to_folder?(folder)
      folder.access_strategy.permits_write_access_for(self)
    end

    def may_create_subfolder_in_folder?(folder)
      folder.access_strategy.permits_subfolders_for(self)
    end

    def media_asset_folder
      Aurita::Plugins::Wiki::Media_Asset_Folder.find(1).with((:user_group_id.eq(user_group_id)) & 
                                                             (:access.eq('PRIVATE')) & 
                                                             (:trashbin.eq('f'))).entity
    end
    alias user_folder media_asset_folder
    alias home_folder media_asset_folder
    alias home_dir media_asset_folder

    def media_asset_folder_id
      folder = media_asset_folder()
      return folder.media_asset_folder_id if folder
      return '0'
    end

  end

end # module
end # module

