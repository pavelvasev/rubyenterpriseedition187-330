# $Id$

=begin
= Pretty-printer for Ruby objects.

== Which seems better?

non-pretty-printed output by (({p})) is:
  #<PP:0x81fedf0 @genspace=#<Proc:0x81feda0>, @group_queue=#<PrettyPrint::GroupQueue:0x81fed3c @queue=[[#<PrettyPrint::Group:0x81fed78 @breakables=[], @depth=0, @break=false>], []]>, @buffer=[], @newline="\n", @group_stack=[#<PrettyPrint::Group:0x81fed78 @breakables=[], @depth=0, @break=false>], @buffer_width=0, @indent=0, @maxwidth=79, @output_width=2, @output=#<IO:0x8114ee4>>

pretty-printed output by (({pp})) is:
  #<PP:0x81fedf0
   @buffer=[],
   @buffer_width=0,
   @genspace=#<Proc:0x81feda0>,
   @group_queue=
    #<PrettyPrint::GroupQueue:0x81fed3c
     @queue=
      [[#<PrettyPrint::Group:0x81fed78 @break=false, @breakables=[], @depth=0>],
       []]>,
   @group_stack=
    [#<PrettyPrint::Group:0x81fed78 @break=false, @breakables=[], @depth=0>],
   @indent=0,
   @maxwidth=79,
   @newline="\n",
   @output=#<IO:0x8114ee4>,
   @output_width=2>

I like the latter.  If you do too, this library is for you.

== Usage

: pp(obj)
    output ((|obj|)) to (({$>})) in pretty printed format.

    It returns (({nil})).

== Output Customization
To define your customized pretty printing function for your classes,
redefine a method (({pretty_print(((|pp|)))})) in the class.
It takes an argument ((|pp|)) which is an instance of the class ((<PP>)).
The method should use PP#text, PP#breakable, PP#nest, PP#group and
PP#pp to print the object.

= PP
== super class
((<PrettyPrint>))

== class methods
--- PP.pp(obj[, out[, width]])
    outputs ((|obj|)) to ((|out|)) in pretty printed format of
    ((|width|)) columns in width.

    If ((|out|)) is omitted, (({$>})) is assumed.
    If ((|width|)) is omitted, 79 is assumed.

    PP.pp returns ((|out|)).

--- PP.singleline_pp(obj[, out])
    outputs ((|obj|)) to ((|out|)) like (({PP.pp})) but with no indent and
    newline.

    PP.singleline_pp returns ((|out|)).

--- PP.sharing_detection
    returns the sharing detection flag as a boolean value.
    It is false by default.

--- PP.sharing_detection = boolean_value
    sets the sharing detection flag.

== methods
--- pp(obj)
    adds ((|obj|)) to the pretty printing buffer
    using Object#pretty_print or Object#pretty_print_cycle.

    Object#pretty_print_cycle is used when ((|obj|)) is already
    printed, a.k.a the object reference chain has a cycle.

--- object_group(obj) { ... }
    is a convenience method which is same as follows:

      group(1, '#<' + obj.class.name, '>') { ... }

--- comma_breakable
    is a convenience method which is same as follows:

      text ','
      breakable

= Object
--- pretty_print(pp)
    is a default pretty printing method for general objects.
    It calls (({pretty_print_instance_variables})) to list instance variables.

    If (({self})) has a customized (redefined) (({inspect})) method,
    the result of (({self.inspect})) is used but it obviously has no
    line break hints.

    This module provides predefined pretty_print() methods for some of
    the most commonly used built-in classes for convenience.

--- pretty_print_cycle(pp)
    is a default pretty printing method for general objects that are
    detected as part of a cycle.

--- pretty_print_instance_variables
    returns a sorted array of instance variable names.

    This method should return an array of names of instance variables as symbols or strings as:
    (({[:@a, :@b]})).

--- pretty_print_inspect
    is (({inspect})) implementation using (({pretty_print})).
    If you implement (({pretty_print})), it can be used as follows.

      alias inspect pretty_print_inspect

== AUTHOR
Tanaka Akira <akr@m17n.org>
=end

require 'prettyprint'

module Kernel
  private
  def pp(*objs)
    objs.each {|obj|
      PP.pp(obj)
    }
    nil
  end
  module_function :pp
end

class PP < PrettyPrint
  def PP.pp(obj, out=$>, width=79)
    q = PP.new(out, width)
    q.guard_inspect_key {q.pp obj}
    q.flush
    #$pp = q
    out << "\n"
  end

  def PP.singleline_pp(obj, out=$>)
    q = SingleLine.new(out)
    q.guard_inspect_key {q.pp obj}
    q.flush
    out
  end

  @sharing_detection = false
  class << self
    attr_accessor :sharing_detection
  end

  module PPMethods
    InspectKey = :__inspect_key__

    def guard_inspect_key
      if Thread.current[InspectKey] == nil
        Thread.current[InspectKey] = []
      end

      save = Thread.current[InspectKey]

      begin
        Thread.current[InspectKey] = []
        yield
      ensure
        Thread.current[InspectKey] = save
      end
    end

    def pp(obj)
      id = obj.__id__

      if Thread.current[InspectKey].include? id
        group {obj.pretty_print_cycle self}
        return
      end

      begin
        Thread.current[InspectKey] << id
        group {obj.pretty_print self}
      ensure
        Thread.current[InspectKey].pop unless PP.sharing_detection
      end
    end

    def object_group(obj, &block)
      group(1, '#<' + obj.class.name, '>', &block)
    end

    def object_address_group(obj, &block)
      group(1, "\#<#{obj.class}:#{("0x%x" % (obj.__id__ * 2)).sub(/\.\.f/, '')}", '>', &block)
    end

    def comma_breakable
      text ','
      breakable
    end

    def pp_object(obj)
      object_address_group(obj) {
        seplist(obj.pretty_print_instance_variables, lambda { text ',' }) {|v|
          breakable
          v = v.to_s if Symbol === v
          text v
          text '='
          group(1) {
            breakable ''
            pp(obj.instance_eval(v))
          }
        }
      }
    end

    def pp_hash(obj)
      group(1, '{', '}') {
        seplist(obj, nil, :each_pair) {|k, v|
          group {
            pp k
            text '=>'
            group(1) {
              breakable ''
              pp v
            }
          }
        }
      }
    end
  end

  include PPMethods

  class SingleLine < PrettyPrint::SingleLine
    include PPMethods
  end

  module ObjectMixin
    # 1. specific pretty_print
    # 2. specific inspect
    # 3. specific to_s if instance variable is empty
    # 4. generic pretty_print

    def pretty_print(q)
      if /\(Kernel\)#/ !~ method(:inspect).inspect
        q.text self.inspect
      elsif /\(Kernel\)#/ !~ method(:to_s).inspect && instance_variables.empty?
        q.text self.to_s
      else
        q.pp_object(self)
      end
    end

    def pretty_print_cycle(q)
      q.object_address_group(self) {
        q.breakable
        q.text '...'
      }
    end

    def pretty_print_instance_variables
      instance_variables.sort
    end

    def pretty_print_inspect
      if /\(PP::ObjectMixin\)#/ =~ method(:pretty_print).inspect
        raise "pretty_print is not overridden."
      end
      PP.singleline_pp(self, '')
    end
  end
end

class Array
  def pretty_print(q)
    q.group(1, '[', ']') {
      q.seplist(self) {|v|
        q.pp v
      }
    }
  end

  def pretty_print_cycle(q)
    q.text(empty? ? '[]' : '[...]')
  end
end

class Hash
  def pretty_print(q)
    q.pp_hash self
  end

  def pretty_print_cycle(q)
    q.text(empty? ? '{}' : '{...}')
  end
end

class << ENV
  def pretty_print(q)
    q.pp_hash self
  end
end

class Struct
  def pretty_print(q)
    q.group(1, '#<struct ' + self.class.name, '>') {
      q.seplist(self.members, lambda { q.text "," }) {|member|
        q.breakable
        q.text member.to_s
        q.text '='
        q.group(1) {
          q.breakable ''
          q.pp self[member]
        }
      }
    }
  end

  def pretty_print_cycle(q)
    q.text sprintf("#<struct %s:...>", self.class.name)
  end
end

class Range
  def pretty_print(q)
    q.pp self.begin
    q.breakable ''
    q.text(self.exclude_end? ? '...' : '..')
    q.breakable ''
    q.pp self.end
  end
end

class File
  class Stat
    def pretty_print(q)
      require 'etc.so'
      q.object_group(self) {
        q.breakable
        q.text sprintf("dev=0x%x", self.dev); q.comma_breakable
        q.text "ino="; q.pp self.ino; q.comma_breakable
        q.group {
          m = self.mode
          q.text sprintf("mode=0%o", m)
          q.breakable
          q.text sprintf("(%s %c%c%c%c%c%c%c%c%c)",
            self.ftype,
            (m & 0400 == 0 ? ?- : ?r),
            (m & 0200 == 0 ? ?- : ?w),
            (m & 0100 == 0 ? (m & 04000 == 0 ? ?- : ?S) :
                             (m & 04000 == 0 ? ?x : ?s)),
            (m & 0040 == 0 ? ?- : ?r),
            (m & 0020 == 0 ? ?- : ?w),
            (m & 0010 == 0 ? (m & 02000 == 0 ? ?- : ?S) :
                             (m & 02000 == 0 ? ?x : ?s)),
            (m & 0004 == 0 ? ?- : ?r),
            (m & 0002 == 0 ? ?- : ?w),
            (m & 0001 == 0 ? (m & 01000 == 0 ? ?- : ?T) :
                             (m & 01000 == 0 ? ?x : ?t)))
        }
        q.comma_breakable
        q.text "nlink="; q.pp self.nlink; q.comma_breakable
        q.group {
          q.text "uid="; q.pp self.uid
          begin
            name = Etc.getpwuid(self.uid).name
            q.breakable; q.text "(#{name})"
          rescue ArgumentError
          end
        }
        q.comma_breakable
        q.group {
          q.text "gid="; q.pp self.gid
          begin
            name = Etc.getgrgid(self.gid).name
            q.breakable; q.text "(#{name})"
          rescue ArgumentError
          end
        }
        q.comma_breakable
        q.group {
          q.text sprintf("rdev=0x%x", self.rdev)
          q.breakable
          q.text sprintf('(%d, %d)', self.rdev_major, self.rdev_minor)
        }
        q.comma_breakable
        q.text "size="; q.pp self.size; q.comma_breakable
        q.text "blksize="; q.pp self.blksize; q.comma_breakable
        q.text "blocks="; q.pp self.blocks; q.comma_breakable
        q.group {
          t = self.atime
          q.text "atime="; q.pp t
          q.breakable; q.text "(#{t.tv_sec})"
        }
        q.comma_breakable
        q.group {
          t = self.mtime
          q.text "mtime="; q.pp t
          q.breakable; q.text "(#{t.tv_sec})"
        }
        q.comma_breakable
        q.group {
          t = self.ctime
          q.text "ctime="; q.pp t
          q.breakable; q.text "(#{t.tv_sec})"
        }
      }
    end
  end
end

class MatchData
  def pretty_print(q)
    q.object_group(self) {
      q.breakable
      q.seplist(1..self.size, lambda { q.breakable }) {|i|
        q.pp self[i-1]
      }
    }
  end
end

class Object
  include PP::ObjectMixin
end

[Numeric, Symbol, FalseClass, TrueClass, NilClass, Module].each {|c|
  c.class_eval {
    def pretty_print_cycle(q)
      q.text inspect
    end
  }
}

[Numeric, FalseClass, TrueClass, Module].each {|c|
  c.class_eval {
    def pretty_print(q)
      q.text inspect
    end
  }
}

if __FILE__ == $0
  require 'test/unit'

  class PPTest < Test::Unit::TestCase
    def test_list0123_12
      assert_equal("[0, 1, 2, 3]\n", PP.pp([0,1,2,3], '', 12))
    end

    def test_list0123_11
      assert_equal("[0,\n 1,\n 2,\n 3]\n", PP.pp([0,1,2,3], '', 11))
    end
  end

  class HasInspect
    def initialize(a)
      @a = a
    end

    def inspect
      return "<inspect:#{@a.inspect}>"
    end
  end

  class HasPrettyPrint
    def initialize(a)
      @a = a
    end

    def pretty_print(q)
      q.text "<pretty_print:"
      q.pp @a
      q.text ">"
    end
  end

  class HasBoth
    def initialize(a)
      @a = a
    end

    def inspect
      return "<inspect:#{@a.inspect}>"
    end

    def pretty_print(q)
      q.text "<pretty_print:"
      q.pp @a
      q.text ">"
    end
  end

  class PrettyPrintInspect < HasPrettyPrint
    alias inspect pretty_print_inspect
  end

  class PrettyPrintInspectWithoutPrettyPrint
    alias inspect pretty_print_inspect
  end

  class PPInspectTest < Test::Unit::TestCase
    def test_hasinspect
      a = HasInspect.new(1)
      assert_equal("<inspect:1>\n", PP.pp(a, ''))
    end

    def test_hasprettyprint
      a = HasPrettyPrint.new(1)
      assert_equal("<pretty_print:1>\n", PP.pp(a, ''))
    end

    def test_hasboth
      a = HasBoth.new(1)
      assert_equal("<pretty_print:1>\n", PP.pp(a, ''))
    end

    def test_pretty_print_inspect
      a = PrettyPrintInspect.new(1)
      assert_equal("<pretty_print:1>", a.inspect)
      a = PrettyPrintInspectWithoutPrettyPrint.new
      assert_raises(RuntimeError) { a.inspect }
    end

    def test_proc
      a = proc {1}
      assert_equal("#{a.inspect}\n", PP.pp(a, ''))
    end

    def test_to_s_with_iv
      a = Object.new
      def a.to_s() "aaa" end
      a.instance_eval { @a = nil }
      result = PP.pp(a, '')
      assert_equal("#{a.inspect}\n", result)
      assert_match(/\A#<Object.*>\n\z/m, result)
      a = 1.0
      a.instance_eval { @a = nil }
      result = PP.pp(a, '')
      assert_equal("#{a.inspect}\n", result)
    end
    
    def test_to_s_without_iv
      a = Object.new
      def a.to_s() "aaa" end
      result = PP.pp(a, '')
      assert_equal("#{a.inspect}\n", result)
      assert_equal("aaa\n", result)
    end
  end

  class PPCycleTest < Test::Unit::TestCase
    def test_array
      a = []
      a << a
      assert_equal("[[...]]\n", PP.pp(a, ''))
      assert_equal("#{a.inspect}\n", PP.pp(a, ''))
    end

    def test_hash
      a = {}
      a[0] = a
      assert_equal("{0=>{...}}\n", PP.pp(a, ''))
      assert_equal("#{a.inspect}\n", PP.pp(a, ''))
    end

    S = Struct.new("S", :a, :b)
    def test_struct
      a = S.new(1,2)
      a.b = a
      assert_equal("#<struct Struct::S a=1, b=#<struct Struct::S:...>>\n", PP.pp(a, ''))
      assert_equal("#{a.inspect}\n", PP.pp(a, ''))
    end

    def test_object
      a = Object.new
      a.instance_eval {@a = a}
      assert_equal(a.inspect + "\n", PP.pp(a, ''))
    end

    def test_anonymous
      a = Class.new.new
      assert_equal(a.inspect + "\n", PP.pp(a, ''))
    end

    def test_withinspect
      a = []
      a << HasInspect.new(a)
      assert_equal("[<inspect:[...]>]\n", PP.pp(a, ''))
      assert_equal("#{a.inspect}\n", PP.pp(a, ''))
    end

    def test_share_nil
      begin
        PP.sharing_detection = true
        a = [nil, nil]
        assert_equal("[nil, nil]\n", PP.pp(a, ''))
      ensure
        PP.sharing_detection = false
      end
    end
  end
end
