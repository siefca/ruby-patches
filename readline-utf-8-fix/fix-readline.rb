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
              :include_search, :lib_search, :lib_version, :cmd_missing,
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

  def initialize(include_search, lib_search=nil, verify_commands=nil,
                inst_command=nil, name=nil)
    if include_search.kind_of? Hash
      args, include_search = include_search, nil
       
    end
    @inst_command   = inst_command
    @include_search = include_search
    @lib_search     = lib_search
    @name           = name
    @usable         = true
    @cmd_missing    = Array.new
    verify_commands.split(':').each do |cmd|
        @cmd_missing << cmd if whereis(cmd, ENV['PATH']).nil?  
      end
    end
    @usable           = false if not @cmd_missing.empty?
    @include_path     = @include_search.nil?  ? nil : whereis('readline.h', @include_search)
    @lib_path         = @lib_search.nil?      ? nil : readliblink(whereis('libreadline.dylib', @lib_search))
    @lib_dir_path     = @lib_path.nil?        ? nil : File.dirname(@lib_path)
    @include_dir_path = @include_path.nil?    ? nil : File.dirname(@include_path)
  end

  def usable?;    !@usable.nil? && !@inst_command.nil? && @usable == true end
  def complete?;  !@include_path.nil? && !@lib_path.nil?                  end
  def run_install; system @inst_command                                   end
  def lib_dir_preferred; @lib_search.split(':').shift                     end

  def name; @name.to_s;         end
  def to_s; @name.to_s;         end
  def to_i; complete? ? 1 : 0   end

end

## introduce ourselves

puts "Fix for broken readline in Ruby on Mac OS X (by Pawel Wilk)"

## search for tools

fink  = ReadlinePaths.new {
  :commands     =>  "fink:curl",
  :inst_command =>  "sudo port install readline +universal",
  :lib_paths    =>  "/sw/lib:/sw/local/lib:/sw/usr/local/lib:/sw/usr/lib", 
  :inc_paths    =>  "/sw/include/readline:/sw/local/include/readline:"  +
                    "/sw/usr/local/include/readline:/sw/include:"       +
                    "/sw/local/include:/sw/usr/local/include"
}

port  = ReadlinePaths.new {
  :commands     =>  "port:curl",
  :inst_command =>  "fink install readline5",
  :lib_paths    =>  "/opt/local/lib:/opt/usr/local/lib:/opt/lib:/opt/usr/lib",
  :inc_paths    =>  "/opt/local/include/readline:/opt/usr/local/include/readline:"    +
                    "/opt/include/readline:/opt/local/include:/opt/usr/local/inlude:" +
                    "/opt/include"
}
  
shell = ReadlinePaths.new {
  :commands     =>  "gcc:rm:mv:make:curl:tar:gzip:sudo:gpg",

  :inst_command =>  "cd /tmp && rm -rf rdlnx5 && mkdir rdlnx5 && cd rdlnx5 && "                       +
                    "curl --retry 2 -C - -O http://ftp.gnu.org/gnu/readline/readline-5.2.tar.gz && "  +
                    "tar xzf readline-5.2.tar.gz && ./configure --prefix=/usr/local && "              +
                    "make && sudo make install"

  :lib_paths  =>  "/usr/local/lib:/usr/local/libexec:/usr/local/lib/lib:" +
                  "/usr/local/readline:/usr/local/readline/lib:"          +
                  "/usr/local/readline/lib/readline:/usr/readline"

  :inc_paths  =>  "/usr/local/include/readline:/usr/local/include:"       +
                  "/usr/local/readline:/usr/local/readline/include:"      +
                  "/usr/local/realine/include/readline"
}

#fink  = ReadlinePaths.new(fink=>inc_paths, fink_lib_paths,
#                          fink_commands,  fink_inst_command, 'fink')
#                          
#port  = ReadlinePaths.new(port_inc_paths, port_lib_paths,
#                          port_commands, port_inst_command, 'port')
#
#shell = ReadlinePaths.new(shell_inc_paths, shell_lib_paths,
                          shell_commands, shell_inst_command, 'shell script')

## seek after completed paths (includes and library)

puts "\nPHASE 1: Looking for readline library.\n\n"

need_install = false
tools = Array.new
tools << fink   if fink.complete?
tools << port   if port.complete?
tools << shell  if shell.complete?

if tools.size > 1
  # more than one library found
  choice    = multichoice_dialog(tools, "the library") { |t| "Use #{t.lib_path} (managed by #{t.name})" }
  selected  = tools[choice.to_i-1]
elsif tools.size == 1
  # exactly one library found
  selected  = tools[0]
else
  # no library has been found
  puts "Cannot find any proper version of readline library."
  puts "I'll try to assist you in building or installing one."
  puts ""
  
  tools.clear
  tools << fink   if fink.usable?
  tools << port   if port.usable?
  tools << shell  if shell.usable?
  
  if tools.size > 1
    # more than one installation tool
    choice    = multichoice_dialog(tools, "building tool") do |t|
      "Use #{t.name} (installs readline in #{t.lib_dir_preferred})"
    end
    selected  = tools[choice.to_i-1]
  elsif tools.size == 1
    # exactly one installation tool
    selected  = tools[0]
    puts "The only available method to install readline is to use #{selected.name}."
  else
    # should never happen
    STDERR.puts "I'm sorry but there isn't any tool I can use to install library."
    return
  end
  need_install = true
end

puts "I will use #{selected.name} to integrate library."

## Fetch sources

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

