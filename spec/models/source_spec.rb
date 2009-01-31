require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Source do
  before(:each) do
    @valid_attributes = {
    }
  end

  it "should load fixtures" do
    Fixtures.create_fixtures(File.join(File.dirname(__FILE__), "..", "..", "db", "migrate"), "sources")
    @source = Source.find(1)
    @source.name.should == "SugarAccounts"
    @source.attributes.size.should == 19
  end
  
  describe "When initializing apapter" do
    it "should accept a class" do
      class Foo
        def initialize(bar, credential);end
      end
      source = Source.new(:adapter => "Foo")
      source.initadapter.should be_a_kind_of(Foo)
    end
    
    it "should accept a module nested class" do
      module Foo2
        class Foo
          def initialize(bar, credential);end
        end
      end
      source = Source.new(:adapter => "Foo2::Foo")
      source.initadapter.should be_a_kind_of(Foo2::Foo)
    end
    it "should accept a multi modules nested class" do
      module Foo4
        module Foo3
          module Foo2
            class Foo
              def initialize(bar, credential);end
            end
          end
        end
      end
      source = Source.new(:adapter => "Foo4::Foo3::Foo2::Foo")
      source.initadapter.should be_a_kind_of(Foo4::Foo3::Foo2::Foo)
    end
  end  
end