def cancel_submission(subs,rt_ticket,login,mode)
  ActiveRecord::Base.transaction do
    comment = "#{Time.now}: Submission cancelled by #{login} via RT ticket #{rt_ticket}"
    odd_classes = ["IlluminaHtp::Requests::CherrypickedToShear","IlluminaHtp::Requests::PostShearToAlLibs","IlluminaHtp::Requests::PrePcrToPcr","IlluminaHtp::Requests::PcrXpToPool","CherrypickForPulldownRequest","IlluminaHtp::Requests::CovarisToSheared"]
    subs.each do |submission_name|
      submission = Submission.find_by_id submission_name
      submission = Submission.find_by_name submission_name unless submission != nil
      submission.name = submission.name+"_failed_RT#{rt_ticket}_1"
      submission.save!
      requests = submission.requests
      requests.each do |r|
        puts "#{r.inspect}"
        if r.class == TransferRequest
          puts "Ignore..."
        else
          status = r.state
          if r.state == "passed"
            if odd_classes.include?(r.class.name)
              r.fail!
              # r.cancel_completed!
              puts "#{submission.id} request #{r.id} #{r.sti_type} was #{status} now => #{r.state}"
            else
              r.change_decision!
              # r.return!
              puts "#{submission.id} request #{r.id} #{r.sti_type} was #{status} now => #{r.state}"
            end
          elsif r.state == "pending"
            r.cancel_before_started!
            puts "#{submission.id} request #{r.id} #{r.sti_type} was #{status} now => #{r.state}"
          else
            puts "#{submission.id} request #{r.id} #{r.sti_type} was #{status} now => #{r.state}"
          end
        end
      end
      puts "Finding SharedLibraryPrep and PcrLibraryRequest requests and deleting.... "
      reqs = submission.requests.select {|r| r.class == IlluminaHtp::Requests::SharedLibraryPrep || r.class == IlluminaC::Requests::PcrLibraryRequest || r.class == IlluminaHtp::Requests::CherrypickedToShear}
      reqs.map(&:delete) unless reqs.empty?
      
      puts "#{Submission.find(submission.id).requests.map(&:state).uniq.inspect}"

      submission.orders.each do |o|
        puts "#{comment}"
        o.comments = comment
        o.save!
      end
    end
    raise "Hell!!" unless mode == "run"
  end; nil
end

cancel_submission(subs,rt_ticket,login,mode)

