#!/usr/bin/env ruby

def whereis(filename, paths)
  paths.split(':').each do |path|
	  path = path + '/' + filename
	  return path if File.readable?(path)
  end
  return nil
end

def readlink(filename)
  return nil if (filename.nil? || filename.empty?)
  begin
    real_path = File.readlink(filename)
  rescue Errno::EINVAL
    return File.readable?(filename) ? filename : nil
  rescue
    return nil
  else
    return real_path
  end
end

def multichoice_dialog(ary, what)
  choice = nil
  until !choice.nil? && (1..ary.size) === choice.to_i
    STDERR.puts " Multiple versions of #{what} were found."
    STDERR.puts " Select one:"
    STDERR.puts
    n = 1
    ary.each do |tool|
      STDERR.puts "   (#{n}) " + yield(tool)
      n += 1
    end
    STDERR.puts
    STDERR.flush
    choice = gets
  end
  return choice
end

class ReadlinePaths
  attr_reader :name, :tool_path, :include_path, :lib_path,
              :include_search, :lib_search, :lib_version,
              :lib_dir_path, :include_dir_path, :inst_command

  def readliblink(filename)
    return nil if (filename.nil? || filename.empty?)
    dirpart = File.dirname filename
    libpath = readlink filename
    return nil if (libpath.nil? || libpath.empty?)

    libpath_full      = File.expand_path(libpath, dirpart)
    libpath_basename  = File.basename libpath
    return nil if (libpath_basename.nil? || libpath_basename.empty?)

    ary = libpath_basename.split '.'
    return nil if (ary.nil? || ary.size < 2)
    @lib_version = ary[1].to_i
    return @lib_version < 5 ? nil : libpath_full
  end

  def initialize(include_search, lib_search, inst_command, name=nil)
    @inst_command   = inst_command
    @include_search = include_search
    @lib_search     = lib_search
    if (!name.nil? && !name.empty?)
      @name         = name
      @tool_path    = whereis(@name, ENV['PATH'])
    else
      @name = @tool_path = :unknown
    end
    @include_path     = whereis('readline.h', @include_search)
    @lib_path         = readliblink(whereis('libreadline.dylib', @lib_search))
    @lib_dir_path     = @lib_path.nil? ? nil : File.dirname(@lib_path)
    @include_dir_path = @include_path.nil? ? nil : File.dirname(@include_path)
  end

  def lib_dir_preferred
    @lib_search.split(':').shift
  end

  def usable?;    !@tool_path.nil? && !@inst_command.nil? end
  def complete?;  !@tool_path.nil? && !@include_path.nil? && !@lib_path.nil? end

  def to_s; @name.to_s; end
  def to_i; complete? ? 1 : 0 end

end

## introduce ourselves

puts "Fix for broken readline in Ruby on Mac OS X (by Pawel Wilk)"

## search for tools

fink_inc_paths = "/sw/include/readline:/sw/local/include/readline:/sw/usr/local/include/readline:/sw/include:/sw/local/include:/sw/usr/local/include"
port_inc_paths = "/opt/local/include/readline:/opt/usr/local/include/readline:/opt/include/readline:/opt/local/include:/opt/usr/local/inlude:/opt/include"
user_inc_paths = "/usr/local/include/readline:/usr/local/include:/usr/local/readline:/usr/local/readline/include:/usr/local/realine/include/readline"

fink_lib_paths = "/sw/lib:/sw/local/lib:/sw/usr/local/lib:/sw/usr/lib"
port_lib_paths = "/opt/local/lib:/opt/usr/local/lib:/opt/lib:/opt/usr/lib"
user_lib_paths = "/usr/local/lib:/usr/local/libexec:/usr/local/lib/lib:/usr/local/readline:/usr/local/readline/lib:/usr/local/readline/lib/readline:/usr/readline"

fink_inst_command = "fink install readline5"
port_inst_command = "sudo port install readline +universal"
user_inst_command = "cd /tmp && mkdir rdlnx5 && cd rdlnx5 && "                            +
                    "wget ftp://ftp.cwru.edu/pub/bash/readline-5.2.tar.gz && "            +
                    "tar xzf readline-5.2.tar.gz && ./configure --prefix=/usr/local && "  +
                    "make && sudo make install"

fink  = ReadlinePaths.new(fink_inc_paths, fink_lib_paths, fink_inst_command, 'fink')
port  = ReadlinePaths.new(port_inc_paths, port_lib_paths, port_inst_command, 'port')
other = ReadlinePaths.new(user_inc_paths, user_lib_paths, user_inst_command)

## seek after completed paths (includes and library)

puts "\nPHASE 1: Looking for readline library in correct version.\n\n"

tools = Array.new
tools << fink   if fink.complete?
tools << port   if port.complete?
tools << other  if other.complete?

if tools.size > 100
  choice    = multichoice_dialog(tools, "the library") { |t| "Use #{t.lib_path} (managed by #{t.name})" }
  selected  = tools[choice.to_i-1]
elsif tools.size == 1
  selected  = tools[0]
else
  puts "Cannot find the proper version of readline library."
  puts "I'll try to assist you to build or install one."
  puts ""
  tools.clear
  tools << fink   if fink.usable?
  tools << port   if port.usable?
  tools << other  if other.usable?
  if tools.size > 1
    choice    = multichoice_dialog(tools, "building tool") do |t|
      "Use #{t.name == :unknown ? 'shell script' : t.name } (installs readline to #{t.lib_dir_preferred})"
    end
    selected  = tools[choice.to_i-1]
  end
end

puts "Selecting readline library in version #{selected.lib_version} managed by #{selected} tool."
puts "Path: #{selected.lib_path}"

## Generate patch

puts "\nPHASE 2: Generating patch\n\n"
puts "Library path:\t"  + "#{selected.lib_dir_path}"

#
# @@ -1,4 +1,6 @@
# require "mkmf"
#+$CFLAGS << " -I/sw/include "
#+$LDFLAGS << " -L/sw/lib "
# 
# $readline_headers = ["stdio.h"]

