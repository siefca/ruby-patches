#!/usr/bin/env ruby

require 'pathname'

class Pathnames < Array

  def initialize(size=0, obj=nil)
    if size.kind_of?(String) && obj.nil?
      super()
      replace(size)
    else
      super(size, obj)
    end
  end

  def replace(other_object)
    if other_object.kind_of?(String)
      other_object = other_object.split(':')
      other_object.map! { |p| Pathname.new(p) }
    end
    return super(other_object)
  end

  def set(pathnames)
    return if pathnames.nil?
    replace(pathnames)
  end

  def expand_paths!
    map! { |p| p.expand_path }
  end

  def expand_paths
    return map { |p| p.dup.expand_path }
  end

  def to_s
    return self.join(':')
  end

  def include?(v)
    if v.kind_of?(String)
      ary = self.map { |p| p.to_s }
      return ary.include?(v)
    else
      return super(v)
    end
  end
  
  def delete(obj)
    if obj.kind_of?(String)
      return self.delete_if { |p| p.to_s == obj }
    else
      return super(v)
    end    
  end

end

class UnixTool < File

  attr_reader :search_paths

  def initialize(filename, mode=nil, perm=nil, search_paths=nil)
    super(filename, mode, perm)
    self.search_paths = search_paths
  end

  def search_paths=(search_paths=nil)
    @search_paths = self.class.get_search_paths(search_paths)
  end

  def whereis(search_paths=nil)
    self.class.expand_path self.path
  end

  def follow_link
    self.class.follow_link(self.path)
  end

  def self.get_search_paths(search_paths=nil)
    search_paths = Pathnames.new(ENV['PATH']) if search_paths.nil?
    if not search_paths.kind_of?(Pathnames)
      search_paths = Pathnames.new(search_paths)
    end
    return search_paths.uniq
  end

  def self.whereis(filename, search_paths=nil, subdir_search=false)
    filename = filename.path if filename.respond_to?(:path)
    return expand_path(filename) if !subdir_search && filename.include?('/')
    paths = get_search_paths(search_paths)
    paths.each do |spath|
      spath = spath + '/' + filename
      return spath if exists?(spath)
    end
    return nil
  end

  def self.follow_link(filename)
    return nil if (filename.nil? || filename.empty?)
    begin
      real_path = readlink(filename)
    rescue Errno::EINVAL
      return readable?(filename) ? filename : nil
    rescue
      return nil
    else
      return real_path
    end
  end

end

class ChoiceDialogs

  def initialize(item_name, objects)
    @item_name  = item_name
    @objects    = objects
  end

  def ask_for_choice
    choice = nil
    until !choice.nil? && (1..@objects.size) === choice.to_i
      STDERR.puts " Multiple incarnations of #{@item_name} were found."
      STDERR.puts " Select one:"
      STDERR.puts
      n = 1
      @objects.each do |obj|
        STDERR.puts "   (#{n}) " + yield(obj)
        n += 1
      end
      STDERR.puts
      STDERR.flush
      choice = gets
    end
    return choice
  end

  def display_list(&block)
    return nil if @objects.nil?
    if @objects.size > 1
      # more than one
      choice    = ask_for_choice &block
      selected  = @objects[choice.to_i-1]
    elsif @objects.size == 1
      # exactly one found
      selected = @objects.first
    else
      # none found
      selected = nil
    end
    return selected
  end

end

class RequiredCommand

  attr_reader :inst_command, :req_commands, :tool_path,
              :cmd_missing, :tool_name, :tool_commands, :bin_search_paths

  # _tool\_name_ - name of a tool,
  # _tool\_cmd_ - command covering tool's existence,
  # _req\_commands_ - colon-separated list of commands required to install,
  # _inst\_command_ - command used to install the tool,
  # _bin_search\_paths - colon-separated list of paths where commands are looked in,
  # (defaults to content of +PATH+ environment variable if not given)
  def initialize(tool_name, tool_command=nil, tool_req_commands=nil,
                 tool_inst_command=nil, bin_search_paths=nil)

    if tool_name.respond_to?(:key?)
      args, tool_name = tool_name, nil
    end

    @tool_name          = get_arg(args, :tool_name,         tool_name)
    @tool_command       = get_arg(args, :tool_commands,     tool_commands)
    @tool_inst_command  = get_arg(args, :inst_command,      inst_command)
    @tool_req_commands  = get_arg(args, :req_commands,      req_commands)
    @bin_search_paths   = get_arg(args, :bin_search_paths,  bin_search_paths)
    @bin_search_paths   = ENV['PATH'] if @bin_search_paths.nil?

    @cmd_missing  = Array.new
    if !@tool_req_commands.nil?
      @tool_req_commands.split(':').each do |cmd|
        @cmd_missing << cmd if UnixTool.whereis(cmd, @bin_search_paths).nil?
      end
    end

    @tool_path = @tool_command.nil? ? nil : UnixTool.whereis(@tool_command, @bin_search_paths)
  end

  def get_arg(hash, name, alternative)
    return (hash.respond_to?(:key?) && hash.key?(name)) ? hash[name] : alternative
  end

  # Returns an array containing required installation commands that are missing, or +nil+
  def missing_install_commands
    @cmd_missing.nil? ? nil : @cmd_missing.dup
  end

  # Returns +true+ if tool command has been found.
  def tool_found?
    !@tool_path.nil? && !@tool_path.empty? 
  end

  def needs_install?
    not tool_found?
  end
  
  def installation_possible?
    @cmd_missing.empty? && !@tool_inst_command.nil?
  end

  # Returns +true+ if it is possible to use installation tool.
  def should_be_installed?
    needs_install? && installation_possible?
  end

  # Runs installation command(s) assgined to a tool.
  def run_install
    installation_possible? ? system(@tool_inst_command) : nil
  end

  # Runs installation command(s) assgined to a tool.
  def install_if_missing
    should_be_installed? ? system(@tool_inst_command) : nil
  end

end

# This class extends class RequiredCommand by adding
# methods and data structures handling common libraries.
#
# This class reads information about library.
# It tracks its version number, pathname of header file,
# pathname of library file, 

class RequiredLibrary < RequiredCommand
  attr_reader :include_path, :lib_path, :lib_name,
  :inc_search_paths, :lib_search_paths, :lib_version,
  :lib_dir_path, :include_dir_path,
  :inc_filename, :lib_filename, :lib_req_ver

# "fink", "readline", 5,
# "readline.h", "libreadline.dylib",
# "/usr/bin", "/usr/lib", "/usr/include",
#  "fink:sudo", "fink install readline4"

# tool_inst_command has changed meaning!!! it's now about the library, not tool

  def initialize(tool_name, lib_name=nil, lib_req_ver=nil,
                 inc_filename=nil, lib_filename=nil,
                 bin_search_paths=nil, lib_search_paths=nil, inc_search_paths=nil,
                 tool_command=nil, tool_req_commands=nil, tool_inst_command=nil)

    if tool_name.respond_to?(:key?)
      args, tool_name = tool_name, nil
      super(args, tool_command, tool_req_commands, tool_inst_command, bin_search_paths)
    else
      super(tool_name, tool_command, tool_req_commands, tool_inst_command, bin_search_paths)
    end

    @inc_search_paths = get_arg(args, :inc_search_paths,     inc_search_paths)
    #new: @search_paths @lib_paths    = get_arg(args, :lib_paths,     lib_paths)
    @lib_name     = get_arg(args, :lib_name,      lib_name)
    @inc_filename = get_arg(args, :inc_filename,  inc_filename)
    @lib_filename = get_arg(args, :lib_filename,  lib_filename)
    @lib_req_ver  = get_arg(args, :lib_req_ver,   lib_req_ver)

    if not @lib_search_paths.nil?
      try_filenames = [ @lib_filename, @lib_filename.sub(/^lib/,''), "lib#{@lib_filename}" ]
      matching_filename = nil
      try_filenames.each do |lib_filename|
        @lib_filename,
        @lib_path,
        @lib_version = readliblink(lib_filename, @lib_search_paths)
        break if not @lib_path.nil?
      end
      @lib_version = nil if @lib_path.nil?
    else
      @lib_path = @lib_version = nil
    end
    
    @include_path     = @inc_search_paths.nil?     ? nil : UnixTool.whereis(@inc_filename, @inc_search_paths)
    @lib_dir_path     = @lib_path.nil?      ? nil : File.dirname(@lib_path)
    @include_dir_path = @include_path.nil?  ? nil : File.dirname(@include_path)
  end

  def readliblink(filename)
    nil_ret = [ filename, nil, nil ]
    return nil_ret if filename.nil?
    filename = UnixTool.whereis(filename, @lib_search_paths)
    return nil_ret if (filename.nil? || filename.empty?)
    dirpart = File.dirname filename
    libpath = UnixTool.follow_link(filename)
    return nil_ret if (libpath.nil? || libpath.empty?)

    libpath_full      = File.expand_path(libpath, dirpart)
    libpath_basename  = File.basename(libpath)
    return nil_ret if (libpath_basename.nil? || libpath_basename.empty?)

    ary = libpath_basename.split '.'
    return nil_ret if (ary.nil? || ary.size < 2)
    lib_version = ary[1].to_i
    return filename, libpath_full, lib_version
  end

  # Returns +true+ if major library version equals required.
  # It uses triple equality operator, so can test ranges.
  def version_ok?
    return true if @lib_req_ver.nil?
    @lib_req_ver === @lib_version
  end

  # Returns true if library has been found.
  # It simply checks whether proper header file
  # exists and library file exists.
  def lib_found?
    !@lib_path.nil?
  end

  def inc_found?
    !@include_path.nil?
  end

  def libfiles_found?
    lib_found? && inc_found?
  end

  # Returns true if library has been found
  # and its version is ok.
  def lib_ok?
    libfiles_found? && version_ok?
  end

  # Creates preferred installation path
  # for the library using first path
  # submitted in _lib\_paths_ while
  # creating new object.
  def lib_dir_preferred
    return nil if @lib_paths.nil?
    @lib_paths.split(':').shift
  end

  # Returns name of a library.
  def name; @lib_name.to_s; end

  # Same as name.
  def to_s; @lib_name.to_s; end

  # Returns 1 if library has been found
  # and 0 otherwise.
  def to_i; lib_ok? ? 1 : 0  end

end

# This class keeps tools.

class Tools <Array

  def add(tool);      self << tool      end
  def remove(tool);   delete(tool)      end

  def usable;         select { |v| v.usable? }          end
  def unusable;       reject { |v| v.usable? }          end
  def with_lib_found; select { |v| v.libfiles_found? }  end
  def with_lib_ok;    select { |v| v.lib_ok? }          end

end

## introduce ourselves

puts "Fix for broken readline in Ruby on Mac OS X (by Pawel Wilk)"

## search for tools

fink  = RequiredLibrary.new(
:tool_name    =>  "fink",
:lib_name     =>  "readline",
:lib_req_ver  =>  (5..6),
:req_commands =>  "fink",
:inst_command =>  "fink install readline5",
:lib_paths    =>  "/sw/lib:/sw/local/lib:/sw/usr/local/lib:/sw/usr/lib",
:inc_search_paths    =>  "/sw/include/readline:/sw/local/include/readline:"  +
                  "/sw/usr/local/include/readline:/sw/include:"       +
                  "/sw/local/include:/sw/usr/local/include",
:inc_filename =>  "readline.h",
:lib_filename =>  "libreadline.dylib"
)

port  = RequiredLibrary.new(
:tool_name    =>  "port",
:lib_name     =>  "readline",
:lib_req_ver  =>  (5..6),
:req_commands =>  "port:sudo",
:inst_command =>  "sudo port install readline +universal",
:lib_paths    =>  "/opt/local/lib:/opt/usr/local/lib:/opt/lib:/opt/usr/lib",
:inc_search_paths    =>  "/opt/local/include/readline:/opt/usr/local/include/readline:"    +
                  "/opt/include/readline:/opt/local/include:/opt/usr/local/inlude:" +
                  "/opt/include",
:inc_filename =>  "readline.h",
:lib_filename =>  "libreadline.dylib"
)

shell = RequiredLibrary.new(
:tool_name    =>  "shell script",
:lib_name     =>  "readline",
:lib_req_ver  =>  (5..6),
:req_commands =>  "gcc:rm:mv:make:curl:tar:gzip:sudo:gpg:git",

:inst_command =>  "rm -rf ./build && ./mkdir build && cd ./build && "                               +
                  "curl --retry 2 -C - -O http://ftp.gnu.org/gnu/readline/readline-5.2.tar.gz && "  +
                  "tar xzf readline-5.2.tar.gz && ./configure --prefix=/usr/local && "              +
                  "make && sudo make install",

:lib_paths  =>  "/usr/local/lib:/usr/local/libexec:/usr/local/lib/lib:" +
                "/usr/local/readline:/usr/local/readline/lib:"          +
                "/usr/local/readline/lib/readline:/usr/readline",

:inc_search_paths  =>  "/usr/local/include/readline:/usr/local/include:"       +
                "/usr/local/readline:/usr/local/readline/include:"      +
                "/usr/local/realine/include/readline",

:inc_filename =>  "readline.h",
:lib_filename =>  "libreadline.dylib"
)

native = RequiredLibrary.new(
:tool_name    =>  "Mac OS X",
:lib_name     =>  "readline",
:lib_req_ver  =>  (5..6),
:lib_paths    =>  "/usr/lib:/lib:/usr/lib/readline:/usr/lib/readline/lib:/System/Library/Frameworks:/Library/Frameworks",
:inc_search_paths    =>  "/usr/include/readline:/usr/include",
:inc_filename =>  "readline.h",
:lib_filename =>  "libreadline.dylib"
)

common_build_tools = Tool.new(
:tool_name    =>  "prerequisites",
:req_commands =>  "gpg:curl:sdfsdf:upa:siefca:lsls",
:inst_command =>  "echo"
)

build_tools_shell = Tools.new [
  RequiredCommand.new("Tape ARchiver",     "tar"),
  RequiredCommand.new("GNU make",          "make"),
  RequiredCommand.new("GNU C Compiler",    "gcc"),
  RequiredCommand.new("GNU Privacy Guard", "gpg"),
  RequiredCommand.new("CURL", "curl")
]

build_tools_fink = Tools.new [
  RequiredCommand.new("Tape ARchiver",   "tar",  "fink", "fink install tar"),
  RequiredCommand.new("GNU make",        "make", "fink", "fink install make"),
  RequiredCommand.new("GNU C Compiler",  "gcc",  "fink", "fink install gcc4"),
]

build_tools_port = Tools.new [
  RequiredCommand.new("Tape ARchiver",   "tar",  "port:sudo", "sudo port install tar"),
  RequiredCommand.new("GNU make",        "make", "port:sudo", "sudo port install make"),
  RequiredCommand.new("GNU C Compiler",  "gcc",  "port:sudo", "sudo port install gcc43"),
]

## Check for tools that we need to build the library

puts "\nPHASE 0: Looking for common tools.\n\n"

ENV['PATH'] += ":/sw/bin:/opt/local/bin:/usr/local/bin"

#if not common_build_tools.usable?
#  STDERR.puts "Mission aborted due to unmet dependencies."
#  STDERR.puts "Tools required to apply this fix that cannot be found in PATH:"
#  common_build_tools.missing_commands.each { |cmd| STDERR.puts " => #{cmd}" }
#  exit 1
#else
#  puts "Found all commands required to apply this fix."
#end

## seek after completed paths (includes and library)

puts "\nPHASE 1: Looking for library.\n\n"

need_install = false

managed_libs = Tools.new
managed_libs.add fink
managed_libs.add port
managed_libs.add shell
managed_libs.add native

choose_readline   = ChoiceDialogs.new('readline library', managed_libs.with_lib_ok)
choose_installer  = ChoiceDialogs.new('installation tool', managed_libs.usable)

library = choose_readline.display_list do |library|
  "Use #{library.lib_path} (managed by #{library.tool_name})"
end

if library.nil?
  needs_install = true
  puts "Cannot find any proper version of readline library."
  puts "I'll try to assist you in building or installing one.\n\n"  
  
  library = choose_installer.display_list do |installer|
    "Use #{installer.tool_name} (installs #{installer.lib_name} in #{installer.lib_dir_preferred})"
  end
else
  puts "I've found version #{library.lib_version} of #{library.lib_name} library in #{library.lib_dir_path}"
end

if library.nil?
  STDERR.puts "I'm sorry but I cannot use any known tool to install the library."
  STDERR.puts "Here are commands that were NOT FOUND required by each tool to run:\n\n"

  managed_libs.unusable.each_with_index do |tool,i|
    if not tool.missing_commands.empty?
      STDERR.puts " [#{i+1}] #{tool.tool_name} requires: #{tool.missing_commands.join(', ')}"
    end
  end
  STDERR.puts

  exit 1
elsif needs_install
  puts "I will use #{library.tool_name} to install readline library." if not library.nil?
  if (library == fink || library == port)
    build_tools.add << gcc
    
  end
end

## Check Ruby version

## Fetch Ruby readline code

## Fetch readline sources

## Generate patch

puts "\nPHASE 2: Generating patch\n\n"
puts "Library path:\t"  + "#{library.lib_dir_path}"

#
# @@ -1,4 +1,6 @@
# require "mkmf"
#+$CFLAGS << " -I/sw/include "
#+$LDFLAGS << " -L/sw/lib "
#
# $readline_headers = ["stdio.h"]
