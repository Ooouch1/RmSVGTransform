require_relative './src/rmSvgTrns'
require 'rexml/document'
require 'logger'

file_path = ARGV[0]
dest_file_path = ARGV[1]

if file_path.nil? #|| dest_file_path.nil?
	p 'parameters are needed: svg_file_path dest_file_path'
end

remover = SVGTransformRemover.new(STDERR)
remover.log_level = Logger::INFO

svg_document = REXML::Document.new(File.open(file_path))

begin
	remover.apply svg_document.root
rescue => e
	puts 'Exited by error.'
	puts e.backtrace.join "\n"
	exit
end
svg_document.write indent: 2, transitive: true
#remover.write File.open(dest_file_path)
