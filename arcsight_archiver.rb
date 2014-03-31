#!/usr/bin/ruby193-ruby
#
# Arcsight has an issue in archiving which is limit archiving space to 200GB even you have more space!.
# The script will move taken archives to another place you specify
# This script is a gift for my colleague Thamer (Abu Abd Allah) to solve arcsight archiving issue
# gem install parseconfig html-table
#
require 'rubygems'
require 'optparse'
require 'parseconfig'
require 'fileutils'
require 'html/table'
require 'net/smtp'
require 'time'
require 'date'
require 'pp'
require 'digest/md5'
require 'viewpoint'



class Check

  #
  # Check given path disk usage. return false if size >= maximum
  #
  def disk_usage(path, max_size, create = false)

    # TODO add option to create destination if not exists
    if create == true
      FileUtils.mkdir_p(path) unless File.exists?(path)
    end
    if current_size(path) >= max_size.to_i
      false
    else
      true
    end

  end

  #
  # Check the size(MB) of the path
  #
  def current_size(path)
    `du -shm #{path}`.match(/^[0-9]+/).to_s.to_i
  end

  #
  # Just simple ls -S1
  #
  def ls(path)
    files = []
    Dir.glob("#{path}/*") {|f| files << f.split('/').last}

    return files
  end


end # Check


class Notify
  include HTML
  include Viewpoint

  def initialize(mail_server, username, password, to_email, cc)
    @endpoint = "https://#{mail_server}/ews/Exchange.asmx"
    @username = username
    @password = password
    @to_email = to_email.split(',')
    @cc       = cc.split(',')
  end

  #
  #
  #
  def send_mail(subject, body)

    subject_ = "ArcSight Archiver | #{subject} - #{Time.new.strftime("%d-%m-%Y")}"

    EWS::EWS.endpoint = @endpoint
    EWS::EWS.set_auth(@username, @password)
    message = EWS::Message

    if @cc.nil? || @cc.empty?
      message.send(subject_, body, @to_email)
    else
      message.send(subject_, body, @to_email, @cc)
    end
  end


  def message(contents)
    source      = ""
    destination = ""
    result         = ""
    date           = Time.new.strftime("%d-%m-%Y")
    table_contents = [["<strong>Archive name</strong>"]]

    contents.each do |content|
      ip_address = content[0]
      file_name  = content[1]
      result     = content[2]
      table_contents << [ip_address , file_name , result , date]
    end

    # Table settings
    table = Table.new(table_contents)
    table.border     = 1
    table[0].align   = "CENTER"
    table[0].colspan = 2
    body             = table.html

    return body
  end

end


class ArcsightArchiver

  def initialize(src, dst, src_max_size, dst_max_size, log_file, keep_days)
    @src = src
    @dst = dst
    @src_max_size = src_max_size
    @dst_max_size = dst_max_size
    @keep_days = keep_days
    @log_file = log_file
    @check = Check.new
    @keep_days = keep_days
  end

  #
  # keep_days calculates the number of days needed to not be archived.
  # so if it's configured to keep last 60 days, it'll calculate from the current day to last 60
  # example: 20140327 - 60 = 20140126
  # return Array of days between 20140327...20140126
  #
  def keep_days
    today = Time.new.strftime('%Y%m%d')
    from_date = Date.parse today
    to_date = (from_date + 1) - @keep_days.to_i # +1 added to from_date to exclude the last day from range

    kept_days = (to_date..from_date).map { |date| date.strftime('%Y%m%d') }.sort
  end

  #
  # move copy folders to the destination then delete it from the source if copy successed
  #
  def move(src, dst)
    # Move should copy first then delete after copying is successfull!
    #FileUtils.cp_r(src, dst, :remove_destination => true).nil?
    FileUtils.rm_rf(src) if FileUtils.cp_r(src, dst, :remove_destination => true).nil?
  rescue Exception => e
    log 3, e
  end

  #
  # Log function
  #
  def log(level_num, message)
    time = Time.new.strftime('%Y-%m-%d %H:%M')

    File.open(@log_file, 'a') { |f| f.puts("#{time} | #{level(level_num)} | #{message}") }
  end


  def level(num)
    level =
        {
        1 => 'alert',
        2 => 'critical',
        3 => 'error',
        4 => 'warning',
        5 => 'notice',
        6 => 'info',
        7 => 'debug'
        }

    level[num]
  end

end # ArcsightArchiver



#                        #
# Settings - Config file #
#                        #
config = ParseConfig.new('./arcsight_archiver.config')
source = config[ 'main' ][ 'archive_source' ]
destination = config[ 'main' ][ 'archive_destination' ]
max_src_disk_usage = config[ 'main' ][ 'max_src_disk_usage' ]
max_dst_disk_usage = config[ 'main' ][ 'max_dst_disk_usage' ]
keep_days = config[ 'main' ][ 'keep_last_days' ]
log_file = config[ 'main' ][ 'log_file' ]

mail_server = config['notifications']['mail_server']
username = config[ 'notifications' ][ 'username' ].split('@').first
password = config[ 'notifications' ][ 'password' ]
to_email = config[ 'notifications' ][ 'to_email' ]
cc_email = config[ 'notifications' ][ 'cc_email' ]



#
# Run
#
begin

  check = Check.new
  archiver = ArcsightArchiver.new(
      source, destination,
      max_src_disk_usage,
      max_dst_disk_usage,
      log_file, keep_days)

  notify = Notify.new(mail_server, username, password, to_email, cc_email)



  # Check if source getting full , then start taking backup
  if !check.disk_usage(source, max_src_disk_usage)

    if check.disk_usage(destination, max_dst_disk_usage)
      move = check.ls(source) - archiver.keep_days
      move.each do |file|
        archiver.move "#{source}/#{file}", destination
      end

      #notify.send_mail 'Archives have been backed up'

    elsif !check.disk_usage(destination, max_dst_disk_usage)
      archiver.log 3, 'Destination disk is full, please release some spaces'
      notify.send_mail(archiver.level(3), "Error: Destination disk is full, please release some spaces")
    end

  else
    archiver.log 6, "Source or Destination doesn't have enough space!"
    notify.send_mail(archiver.level(6), "Source or Destination doesn't have enough space!")
  end


rescue Exception => e
  archiver.log 2, e
  notify.send_mail(archiver.level(2), "#{e}")
end


