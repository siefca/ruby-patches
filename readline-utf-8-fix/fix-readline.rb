#!/usr/bin/env ruby

def whereis(filename, paths)
  paths.split(':').each do |path|
	  path = path + '/' + filename
	  return path if File.exists?(path)
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
    STDERR.puts " Multiple incarnations of #{what} were found."
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
  attr_reader :usable, :inst_command, :include_path, :lib_path,
              :include_search, :lib_search, :lib_version, :cmd_notfound,
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

  def initialize(include_search, lib_search, verify_commands,
                inst_command, name=nil)
    @inst_command   = inst_command
    @include_search = include_search
    @lib_search     = lib_search
    @name           = name
    @usable         = true
    @cmd_notfound   = Array.new
    verify_commands.split(':').each do |cmd|
      if whereis(cmd, ENV['PATH']).nil?
        @usable = false
        @cmd_notfound << cmd
      end
    end
    @include_path     = @include_search.nil?  ? nil : whereis('readline.h', @include_search)
    @lib_path         = @lib_search.nil?      ? nil : readliblink(whereis('libreadline.dylib', @lib_search))
    @lib_dir_path     = @lib_path.nil?        ? nil : File.dirname(@lib_path)
    @include_dir_path = @include_path.nil?    ? nil : File.dirname(@include_path)
  end

  def lib_dir_preferred
    @lib_search.split(':').shift
  end

  def usable?;    !@usable.nil? && !@inst_command.nil? && @usable == true end
  def complete?;  !@include_path.nil? && !@lib_path.nil? end

  def name; @name.to_s; end
  def to_s; @name.to_s; end
  def to_i; complete? ? 1 : 0 end

end

## introduce ourselves

puts "Fix for broken readline in Ruby on Mac OS X (by Pawel Wilk)"

## search for tools

fink_commands   = "fink"
port_commands   = "port"
shell_commands  = "gcc:rm:make:curl:tar:gzip:sudo"
 
fink_lib_paths  =  "/sw/lib:/sw/local/lib:/sw/usr/local/lib:/sw/usr/lib"
port_lib_paths  =  "/opt/local/lib:/opt/usr/local/lib:/opt/lib:/opt/usr/lib"
shell_lib_paths =  "/usr/local/lib:/usr/local/libexec:/usr/local/lib/lib:/usr/local/readline:"       +
                  "/usr/local/readline/lib:/usr/local/readline/lib/readline:/usr/readline"

fink_inc_paths  =  "/sw/include/readline:/sw/local/include/readline:/sw/usr/local/include/readline:" +
                  "/sw/include:/sw/local/include:/sw/usr/local/include"
port_inc_paths  =  "/opt/local/include/readline:/opt/usr/local/include/readline:"                    +
                  "/opt/include/readline:/opt/local/include:/opt/usr/local/inlude:/opt/include"
shell_inc_paths =  "/usr/local/include/readline:/usr/local/include:/usr/local/readline:"             +
                  "/usr/local/readline/include:/usr/local/realine/include/readline"

fink_inst_command   = "fink install readline5"
port_inst_command   = "sudo port install readline +universal"
shell_inst_command  = "cd /tmp && rm -rf rdlnx5 && mkdir rdlnx5 && cd rdlnx5 && "                       +
                      "curl --retry 2 -C - -O http://ftp.gnu.org/gnu/readline/readline-5.2.tar.gz && "  +
                      "tar xzf readline-5.2.tar.gz && ./configure --prefix=/usr/local && "              +
                      "make && sudo make install"

fink  = ReadlinePaths.new(fink_inc_paths, fink_lib_paths,
                          fink_commands,  fink_inst_command, 'fink')
                          
port  = ReadlinePaths.new(port_inc_paths, port_lib_paths,
                          port_commands, port_inst_command, 'port')

shell = ReadlinePaths.new(shell_inc_paths, shell_lib_paths,
                          shell_commands, shell_inst_command, 'shell script')

## seek after completed paths (includes and library)

puts "\nPHASE 1: Looking for readline library.\n\n"

tools = Array.new
tools << fink   if fink.complete?
tools << port   if port.complete?
tools << shell  if shell.complete?

if tools.size > 100
  choice    = multichoice_dialog(tools, "the library") { |t| "Use #{t.lib_path} (managed by #{t.name})" }
  selected  = tools[choice.to_i-1]
elsif tools.size == 1
  selected  = tools[0]
else
  puts "Cannot find any proper version of readline library."
  puts "I'll try to assist you in building or installing one."
  puts ""
  tools.clear
  tools << fink   if fink.usable?
  tools << port   if port.usable?
  tools << shell  if shell.usable?
  if tools.size > 1
    choice    = multichoice_dialog(tools, "building tool") do |t|
      "Use #{t.name} (installs readline in #{t.lib_dir_preferred})"
    end
    selected  = tools[choice.to_i-1]
  else
    selected  = tools[0]
    puts "The only available method to install readline is to use #{selected.name}."
  end
end

puts "I will later use #{selected.name} to install library."
puts "Wanted installation path: #{selected.lib_path}"

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

