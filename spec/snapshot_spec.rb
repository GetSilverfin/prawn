# encoding: utf-8

require File.join(File.expand_path(File.dirname(__FILE__)), "spec_helper")

describe "Prawn::Document#transaction" do

  it "should properly commit if no error is raised" do
    pdf = Prawn::Document.new do
      transaction do
        text "This is shown"
      end
    end
    text = PDF::Inspector::Text.analyze(pdf.render)
    text.strings.should == ["This is shown"]
  end

  it "should not display text if transaction is rolled back" do
    pdf = Prawn::Document.new do
      transaction do
        text "This is not shown"
        rollback
      end
    end
    text = PDF::Inspector::Text.analyze(pdf.render)
    text.strings.should == []
  end

  it "should return true/false value indicating success of the transaction" do
    Prawn::Document.new do
      success = transaction { }
      success.should == true

      success = transaction { rollback }
      success.should == false
    end
  end

  it "should support nested transactions" do
    pdf = Prawn::Document.new do
      transaction do
        text "This is shown"
        transaction do
          text "and this is not"
          rollback
        end
        text "and this is"
      end
    end
    text = PDF::Inspector::Text.analyze(pdf.render)
    text.strings.should == ["This is shown", "and this is"]
  end

  it "should allow rollback of multiple pages" do
    pdf = Prawn::Document.new do
      transaction do
        5.times { start_new_page }
        text "way out there and will never be shown"
        rollback
      end
      text "This is the real text, only one page"
    end

    pages = PDF::Inspector::Page.analyze(pdf.render).pages
    pages.size.should == 1
  end

  it "should give a valid page count when rolling back with a new page" do
    pdf = Prawn::Document.new do
      transaction do
        start_new_page
        text "way out there and will never be shown"
        rollback
      end
      text "This is the real text, on the first page"
    end

    pdf.page_count.should == 1

    # pdf.render_file('test.pdf')
  end

  it "should reset the color space when rolling back" do
    pdf = Prawn::Document.new do
      transaction do
        stroke_color('FFFFF')
        rollback
      end
    end

    pdf.graphic_state.color_space.should == {}
  end

  it "should set the color space after a roll back" do
    require "tempfile"
    pdf = Prawn::Document.new do
      start_new_page(:layout => :landscape)

      group do
        fill_color '000000'

        group do
          %w{3 2 1 a b c d e  f  g  h  i  j  k  l  m  n  o  p  q  r  s  t  u  v  w  x y z}.each do |f|
            text f
            text f
          end
        end
      end
    end

    tempfile = Tempfile.new("generate_test")

    pdf.render_file(tempfile)
    output = `gs -o /dev/null -sDEVICE=nullpage #{tempfile.path} 2>&1`
    output.should_not include('errors')
  end

  it "should not propagate a RollbackTransaction outside its bounds" do
    def add_lines(pdf)
      100.times { |i| pdf.text "Line #{i}" }
    end

    Prawn::Document.new do |pdf|
      lambda do
        begin
          pdf.group { add_lines(pdf) }
        rescue Prawn::Errors::CannotGroup
          add_lines(pdf)
        end
      end.should_not raise_error#(Prawn::Document::Snapshot::RollbackTransaction)
    end
  end

  # Because the Pages object, when restored, points to the snapshotted pages
  # by identifier, we have to restore the snapshot into the same page objects,
  # or else old pages will appear in the post-rollback document.
  it "should restore the pages into the same objects" do
    Prawn::Document.new do
      old_page_object_id = state.page.dictionary.identifier
      old_page_content_id = state.page.content.identifier

      transaction do
        start_new_page
        rollback
      end

      state.page.dictionary.identifier.should == old_page_object_id
      state.page.content.identifier.should == old_page_content_id
    end

  end

  it "page object should refer to the page_content object after restore" do

    Prawn::Document.new do
      transaction do
        start_new_page
        rollback
      end

      # should be the exact same object, not a clone
      state.page.dictionary.data[:Contents].should == state.page.content
    end

  end

  it "should restore bounds on rollback" do
    Prawn::Document.new(:page_layout => :landscape) do
      size = [bounds.width, bounds.height]
      transaction do
        start_new_page :layout => :portrait
        rollback
      end
      [bounds.width, bounds.height].should == size
    end
  end

  it "should set new bounding box on start_new_page with different layout" do
    Prawn::Document.new(:page_layout => :landscape) do
      size = [bounds.width, bounds.height]
      transaction do
        start_new_page
        rollback
      end

      start_new_page :layout => :portrait
      [bounds.width, bounds.height].should == size.reverse
    end
  end

  it "should work with dests" do
    Prawn::Document.new do |pdf|
      pdf.add_dest("dest", pdf.dest_fit_horizontally(pdf.cursor, pdf.page))
      pdf.text("Hello world")
      lambda { pdf.transaction{} }.should_not raise_error
    end
  end

  describe "with a stamp dictionary present" do

    it "should properly commit if no error is raised" do
      pdf = Prawn::Document.new do
        create_stamp("test_stamp") { draw_text "This is shown", :at => [0,0] }
        transaction do
          stamp("test_stamp")
        end
      end
      pdf.render.should =~ /\/Stamp1 Do/
    end

    it "should properly rollback when #rollback is called" do
      pdf = Prawn::Document.new do
        create_stamp("test_stamp") { draw_text "This is not shown", :at => [0,0] }

        transaction do
          stamp("test_stamp")
          rollback
        end
      end
      pdf.render.should_not =~ /\/Stamp1 Do/
    end

  end

  it "should restore page_number on rollback" do
    Prawn::Document.new do
      transaction do
        5.times { start_new_page }
        rollback
      end

      page_number.should == 1
    end
  end

  it "should restore multiple content streams" do
    pdf = Prawn::Document.new(page_size: "A4", skip_page_creation: true);
    pdf.start_new_page(:template => "#{Prawn::BASEDIR}/spec/data/curves.pdf", :template_page => 1, size: "A4")
    pdf.text 'test 1'
    pdf.transaction{pdf.text 'test 2'; pdf.rollback}
    output = StringIO.new(pdf.render)
    hash = PDF::Reader::ObjectHash.new(output)
    pages = hash.values.find {|obj| obj.is_a?(Hash) && obj[:Type] == :Pages}[:Kids]
    template_page = hash[pages[0]]
    template_page[:Contents].size.should == 2
  end
end

