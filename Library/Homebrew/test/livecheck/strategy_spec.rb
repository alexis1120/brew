# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy do
  subject(:strategy) { described_class }

  let(:url) { "https://brew.sh/" }
  let(:redirection_url) { "https://brew.sh/redirection" }

  let(:data_hash) do
    {
      "empty"   => "",
      "boolean" => "true",
      "number"  => "1",
      "string"  => "a + b = c",
    }
  end
  let(:data_string) { "empty=&boolean=true&number=1&string=a+%2B+b+%3D+c" }
  let(:json_string) { '{"empty":"","boolean":"true","number":"1","string":"a + b = c"}' }

  let(:response_hash) do
    response_hash = {}

    response_hash[:ok] = {
      status_code: "200",
      status_text: "OK",
      headers:     {
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Thu, 1 Jan 2019 01:23:45 GMT",
        "content-length" => "123",
      },
    }

    response_hash[:redirection] = {
      status_code: "301",
      status_text: "Moved Permanently",
      headers:     {
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Thu, 1 Jan 2019 01:23:45 GMT",
        "content-length" => "123",
        "location"       => redirection_url,
      },
    }

    response_hash
  end

  let(:body) do
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <title>Thank you!</title>
        </head>
        <body>
          <h1>Download</h1>
          <p>This download link could have been made publicly available in a reasonable fashion but we appreciate that you jumped through the hoops that we carefully set up!: <a href="https://brew.sh/example-1.2.3.tar.gz">Example v1.2.3</a></p>
          <p>The current legacy version is: <a href="https://brew.sh/example-0.1.2.tar.gz">Example v0.1.2</a></p>
        </body>
      </html>
    HTML
  end

  let(:response_text) do
    response_text = {}

    response_text[:ok] = <<~EOS
      HTTP/1.1 #{response_hash[:ok][:status_code]} #{response_hash[:ok][:status_text]}\r
      Cache-Control: #{response_hash[:ok][:headers]["cache-control"]}\r
      Content-Type: #{response_hash[:ok][:headers]["content-type"]}\r
      Date: #{response_hash[:ok][:headers]["date"]}\r
      Expires: #{response_hash[:ok][:headers]["expires"]}\r
      Last-Modified: #{response_hash[:ok][:headers]["last-modified"]}\r
      Content-Length: #{response_hash[:ok][:headers]["content-length"]}\r
      \r
      #{body.rstrip}
    EOS

    response_text[:redirection_to_ok] = response_text[:ok].sub(
      "HTTP/1.1 #{response_hash[:ok][:status_code]} #{response_hash[:ok][:status_text]}\r",
      "HTTP/1.1 #{response_hash[:redirection][:status_code]} #{response_hash[:redirection][:status_text]}\r\n" \
      "Location: #{response_hash[:redirection][:headers]["location"]}\r",
    )

    response_text
  end

  describe "::from_symbol" do
    it "returns the Strategy module represented by the Symbol argument" do
      expect(strategy.from_symbol(:page_match)).to eq(Homebrew::Livecheck::Strategy::PageMatch)
    end
  end

  describe "::from_url" do
    let(:url) { "https://sourceforge.net/projects/test" }

    context "when no regex is provided" do
      it "returns an array of usable strategies which doesn't include PageMatch" do
        expect(strategy.from_url(url)).to eq([Homebrew::Livecheck::Strategy::Sourceforge])
      end
    end

    context "when a regex is provided" do
      it "returns an array of usable strategies including PageMatch, sorted in descending order by priority" do
        expect(strategy.from_url(url, regex_provided: true))
          .to eq(
            [Homebrew::Livecheck::Strategy::Sourceforge, Homebrew::Livecheck::Strategy::PageMatch],
          )
      end
    end
  end

  describe "::post_args" do
    it "returns an array including `--data` and an encoded form data string" do
      expect(strategy.post_args({ data: data_hash })).to eq(["--data", data_string])
      expect(strategy.post_args({ data: data_string })).to eq(["--data", data_string])
    end

    it "returns an array including `--json` and a JSON string" do
      expect(strategy.post_args({ json: data_hash })).to eq(["--json", json_string])
      expect(strategy.post_args({ json: json_string })).to eq(["--json", json_string])
    end

    it "returns an empty array if `data` value is blank" do
      expect(strategy.post_args({ data: "" })).to eq([])
      expect(strategy.post_args({ data: {} })).to eq([])
    end

    it "returns an empty array if hash argument doesn't have a `data` or `json` value" do
      expect(strategy.post_args({ not_data: "oops" })).to eq([])
      expect(strategy.post_args({})).to eq([])
    end
  end

  describe "::page_headers" do
    let(:responses) { [response_hash[:ok]] }

    it "returns headers from fetched content" do
      allow(strategy).to receive(:curl_headers).and_return({ responses:, body: })

      expect(strategy.page_headers(url)).to eq([responses.first[:headers]])
    end

    it "handles `method: :post` `url` options" do
      allow(strategy).to receive(:curl_headers).and_return({ responses:, body: })

      expect(strategy.page_headers(url, url_options: { method: :post, data: data_hash }))
        .to eq([responses.first[:headers]])
    end

    it "returns an empty array if `curl_headers` only raises an `ErrorDuringExecution` error" do
      allow(strategy).to receive(:curl_headers).and_raise(ErrorDuringExecution.new([], status: 1))

      expect(strategy.page_headers(url)).to eq([])
    end
  end

  describe "::page_content" do
    let(:curl_version) { Version.new("8.7.1") }
    let(:success_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }

    it "returns hash including fetched content" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([response_text[:ok], nil, success_status])

      expect(strategy.page_content(url)).to eq({ content: body })
    end

    it "handles `method: :post` `url` options" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([response_text[:ok], nil, success_status])

      expect(strategy.page_content(url, url_options: { method: :post, data: data_hash })).to eq({ content: body })
    end

    it "returns error `messages` from `stderr` in the return hash on failure when `stderr` is not `nil`" do
      error_message = "curl: (6) Could not resolve host: brew.sh"
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([
        nil,
        error_message,
        instance_double(Process::Status, success?: false, exitstatus: 6),
      ])

      expect(strategy.page_content(url)).to eq({ messages: [error_message] })
    end

    it "returns default error `messages` in the return hash on failure when `stderr` is `nil`" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([
        nil,
        nil,
        instance_double(Process::Status, success?: false, exitstatus: 1),
      ])

      expect(strategy.page_content(url)).to eq({ messages: ["cURL failed without a detectable error"] })
    end

    it "returns hash including `final_url` if it differs from initial `url`" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([response_text[:redirection_to_ok], nil, success_status])

      expect(strategy.page_content(url)).to eq({ content: body, final_url: redirection_url })
    end
  end

  describe "::handle_block_return" do
    it "returns an array of version strings when given a valid value" do
      expect(strategy.handle_block_return("1.2.3")).to eq(["1.2.3"])
      expect(strategy.handle_block_return(["1.2.3", "1.2.4"])).to eq(["1.2.3", "1.2.4"])
    end

    it "returns an empty array when given a nil value" do
      expect(strategy.handle_block_return(nil)).to eq([])
    end

    it "errors when given an invalid value" do
      expect { strategy.handle_block_return(123) }
        .to raise_error(TypeError, strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end
  end
end
