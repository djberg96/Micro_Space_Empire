require "./spec_helper"

describe MicroSpaceEmpire::Content do
  it "loads and validates every definition and asset pair" do
    CONTENT.validate!(ROOT)
    CONTENT.systems.size.should eq(13)
    CONTENT.systems.values.count(&.expansion).should eq(2)
    CONTENT.events.size.should eq(11)
    CONTENT.events.values.count(&.expansion).should eq(3)
    CONTENT.technologies.size.should eq(8)
  end

  it "uses the original Asteroid values" do
    asteroid = CONTENT.events["asteroid"]
    asteroid.resource.should eq("wealth")
    asteroid.value(1).should eq(1)
    asteroid.value(2).should eq(1)
  end

  it "loads its embedded content and artwork without the project directories" do
    embedded = MicroSpaceEmpire::Content.load(Dir.tempdir)
    embedded.validate!(Dir.tempdir)
    embedded.systems.size.should eq(13)
    embedded.events.size.should eq(11)
  end
end
