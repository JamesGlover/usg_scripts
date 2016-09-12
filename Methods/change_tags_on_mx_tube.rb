module ChangeTags

  VERSION = "change_tag_on_mx_tube_std_order.rb version 2.2"
  EXCLUDED_CLASSES = [QcTube]

  def self.set_false_tags(lib_ids)
    puts "Clearing library id on: #{lib_ids}"
    Aliquot.where(library_id:lib_ids).joins(:receptacle).where('assets.sti_type NOT IN (?)',EXCLUDED_CLASSES.map(&:name)).update_all(tag_id: nil)
  end

  def self.change_tags(mx,lib_aliquots,sample_tag_hash,tag_group,rt_ticket,user,version)
    tag_map = Hash[tag_group.tags.map {|tag| [tag.map_id,tag.id] }]
    i = 0
    lib_aliquots.find_each do |aliquot|
      aliquot.tag_id = tag_map[sample_tag_hash[aliquot.sample.name]]
      aliquot.save!
      aliquot.reload
      puts "#{i} >> #{aliquot.receptacle.class.name} aliquot: #{aliquot.id} => Sample: #{aliquot.sample.name} => new tag: #{aliquot.tag.map_id} - #{aliquot.tag_id}"
      i +=1
    end
  end

  def self.change_tags_on_mx(tags,tag_group,mx_tube,mode,rt_ticket,login)
    version = VERSION
    puts "Supply: tags (in correct order i.e [1,2,4,8,3,5,6,7], tag_group (id), mx_tube (id), mode ('test'/'run')\n"
    puts "Running in test mode\n" unless mode == "run"
    ActiveRecord::Base.uncached do
      ActiveRecord::Base.transaction do

        user = User.find_by_login login
        mx = Asset.where(id:mx_tube).includes(aliquots: :sample).first!


        # find the library id's of the mx_tube
        lib_ids = mx.aliquots.map(&:library_id)
        samples = mx.aliquots.map(&:sample).flatten.map(&:name).uniq
        lib_aliquots = Aliquot.where(library_id:lib_ids).joins(:receptacle).where('assets.sti_type NOT IN (?)',EXCLUDED_CLASSES.map(&:name)).select('aliquots.*').preload(:sample,:receptacle,:library)


        sample_tag_hash = Hash[samples.zip(tags)]
        keys = sample_tag_hash.keys; nil
        problems = samples - keys
        if problems.empty?
          puts "Hash and mx.aliquots match. Proceeding..."
        else
          puts "Problems...\n#{problems.inspect}\n"
          raise "hash keys and mx samples do not match"
        end

        # Add comments before we clear the original tags
        puts "Adding comments..."
        comment_on = lambda { |x,text| x.comments.create!(:description => text, :user_id => user.id, :title => "Tag change #{rt_ticket}") }
        Asset.where(id:lib_ids).includes(aliquots:{tag: :tag_group}).uniq.each do |lib|
          comment_text = "#{user.login} changed tag from tag_group #{lib.aliquots.first.tag.tag_group.id} - tag #{lib.aliquots.first.tag.map_id} => tag_group #{tag_group} - tag #{sample_tag_hash[lib.aliquots.first.sample.name]} requested via RT ticket #{rt_ticket} using #{version}"
          comment_on.call(lib,comment_text)
        end

        comment_text = "MX tube tags updated via RT#{rt_ticket}"
        comment_on = lambda { |x| x.comments.create!(:description => comment_text, :user_id => user.id, :title => "Tag change #{rt_ticket}") }
        comment_on.call(mx)

        puts "sample_tag_hash: #{sample_tag_hash.inspect}\n\n"
        puts "Setting false tags on libraries"
        set_false_tags(lib_ids)

        puts "Assigning new tags"
        change_tags(mx,lib_aliquots,sample_tag_hash,tag_group,rt_ticket,user,version)

        raise "TESTING *********" unless mode == "run"
      end
    end
  end
end
ActiveRecord::Base.logger.level = 3
ChangeTags.change_tags_on_mx(tags,tag_group,mx_tube,mode,rt_ticket,login)
