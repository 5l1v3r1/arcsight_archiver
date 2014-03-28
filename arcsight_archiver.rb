#!/usr/bin/env ruby
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


class Check

  #
  # Check given path disk usage
  #
  def disk_usage(path, max_size)

    return false unless File.exists?(path)

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
  #
  #
  def integrity(src, dst)
    Dir.glob('/opt/arcsight/logger/data/archives_backup/20140223/*') {|f| puts f}
  end


  def md5(src, dst)
    case
      when Digest::MD5.hexdigest(src) == Digest::MD5.hexdigest(dst)
        true
      when Digest::MD5.hexdigest(src) != Digest::MD5.hexdigest(dst)
        false
    end
  end

  def ls(path)
    files = []
    Dir.glob("#{path}/*") {|f| files << f.split('/').last}

    return files
  end


end # Check


class Notify
  include HTML

  def initialize(smtp_server, port, from_email, to_email, cc='', subject)
    @smtp_server  = "localhost"                                             # Put your smtp server here
    @port         = 25                                                      # SMTP port
    @from_email   = "arcsight@mohe.gov.sa"                       	# Sender e-mail
    @to_email     = "sabri@security4arabs.net"                              # Receiver e-mail
    @cc           = "king.sabri@gmail.com"                                  # Comment this line if there is no Cc
    @subject      = "ArcSight Archiver - #{Time.new.strftime("%d-%m-%Y")}"     # e-mail's Subject - date
    @mime         = "MIME-Version: 1.0"
    @content_type = "Content-type: text/html"
  end

  def error

  end

  def success

  end

  def message(full_result)
    source      = ""
    destination = ""
    result         = ""
    url            = ""
    date           = Time.new.strftime("%d-%m-%Y")
    table_contents = [["<strong>Archive name</strong>"]]

    full_result.each do |res|
      ip_address = res[0]
      file_name  = res[1]
      result     = res[2]
      url        = res[5]
      table_contents << [ip_address , file_name , result , url , date]
    end
    table = Table.new(table_contents)
    table.border     = 1
    table[0].align   = "CENTER"
    table[0].colspan = 2
    body             = table.html

    return body
  end

  def send_mail(message)
    Net::SMTP.start(@smtp_server, @port) do |smtp|
      smtp.set_debug_output $stderr
      smtp.open_message_stream(@from_email, @to_email) do |f|
        f.puts "From: #{@from_email}"
        f.puts "To: #{@to_email}"
        f.puts "Cc: #{@cc}"                                 # Comment this line if there is no Cc
        f.puts "Subject: #{@subject}"
        f.puts @mime
        f.puts @content_type
        f.puts "#{message}"
      end
    end
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
    puts e
  end

  #
  # Log function
  #
  def log(level_num, message)
    time = Time.new.strftime('%Y-%m-%d %H:%M')

    File.open(@log_file, 'a') { |f| f.puts("#{time} | #{level(level_num)} | #{message}") }

  end

  protected
  def level(num)
    level= {
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

end




#
# Settings - Config file
#
config = ParseConfig.new('./arcsight_archiver.config')
source = config[ 'main' ][ 'archive_source' ]
destination = config[ 'main' ][ 'archive_destination' ]
max_src_disk_usage = config[ 'main' ][ 'max_src_disk_usage' ]
max_dst_disk_usage = config[ 'main' ][ 'max_dst_disk_usage' ]
keep_days = config[ 'main' ][ 'keep_last_days' ]
log_file = config[ 'main' ][ 'log_file' ]
smtp_server = config['notifications']['smtp_server']
from_email = config[ 'notifications' ][ 'from_email' ]
to_email = config[ 'notifications' ][ 'to_email' ]
cc_email = 'securityteam@mail.com'
subject_email = config[ 'notifications' ][ 'subject_email' ]


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
  notify = Notify.new(smtp_server, from_email, to_email, subject_email)

  if check.disk_usage(source, max_src_disk_usage) && check.disk_usage(destination, max_dst_disk_usage)
    # exclude the keep_days from moving to destination
    move = check.ls(source) - archiver.keep_days

    move.each do |file|
      archiver.move "#{source}/#{file}", destination
    end
  else
    archiver.log 3, "Source or Destination doesn't have enough space!"
  end

rescue Exception => e
  archiver.log 2, 'Something goes wrong'
end





#date = Date.parse '20140111'
## subtract 2 months
##(date << 2).strftime('%Y%m%d')
#( date - 60 ).strftime('%Y%m%d')
#
## All days
#date1 = Date.parse '20140111'
#date2 = ( date1 - DAYS )
#(date2..date1).map do |date|
#  "Date: #{date.strftime('%Y%m%d')}"
#end


