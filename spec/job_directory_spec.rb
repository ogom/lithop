# frozen_string_literal: true

RSpec.describe Lithop::JobDirectory do
  it "removes its temporary directory when publishing fails" do
    Dir.mktmpdir do |project_dir|
      job = described_class.new(project_dir:, job_id: "job")
      allow(File).to receive(:rename).and_raise(Errno::ENOSPC)

      expect { job.call { |directory| File.write(File.join(directory, "artifact"), "data") } }
        .to raise_error(Errno::ENOSPC)
      expect(Dir).not_to exist(job.temporary)
      expect(Dir).not_to exist(job.destination)
    end
  end

  it "preserves the original error when cleanup also fails" do
    Dir.mktmpdir do |project_dir|
      job = described_class.new(project_dir:, job_id: "job")
      original_error = Errno::ENOSPC.new
      allow(FileUtils).to receive(:rm_rf).and_raise(Errno::EACCES)

      expect { job.call { raise original_error } }.to raise_error(original_error)
    end
  end

  it "does not remove a temporary directory owned by another run" do
    Dir.mktmpdir do |project_dir|
      job = described_class.new(project_dir:, job_id: "job")
      FileUtils.mkdir_p(job.temporary)
      sentinel = File.join(job.temporary, "owner")
      File.write(sentinel, "keep")

      expect { job.call { raise "not reached" } }.to raise_error(Lithop::Error, /output already exists/)
      expect(File.read(sentinel)).to eq("keep")
    end
  end
end
