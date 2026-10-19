namespace :users do
  desc "Create or promote an approved admin. Usage: bin/rails 'users:create_admin[username,email,password]'"
  task :create_admin, %i[username email password] => :environment do |_task, args|
    username, email, password = args.values_at(:username, :email, :password)
    abort "Usage: bin/rails 'users:create_admin[username,email,password]'" if username.blank?

    user = User.find_by_login(username) || User.new(username: username)
    user.email_address = email if email.present?
    user.password = password if password.present?
    user.assign_attributes(admin: true, approval_state: :approved)
    user.save!

    puts "#{user.username} is an approved admin."
  end
end
