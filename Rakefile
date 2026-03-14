require 'puppetlabs_spec_helper/rake_tasks'
require 'puppet-lint/tasks/puppet-lint'
require 'puppet-syntax/tasks/puppet-syntax'

PuppetLint.configuration.send('disable_140chars')
PuppetLint.configuration.relative = true
PuppetLint.configuration.ignore_paths = ['spec/**/*.pp', 'pkg/**/*.pp', 'vendor/**/*.pp']
PuppetLint.configuration.send('disable_arrow_on_right_operand_line')

desc 'Validate manifests and templates'
task :validate do
  Dir['manifests/**/*.pp'].each do |manifest|
    sh "puppet parser validate --noop #{manifest}"
  end
  Dir['templates/**/*.erb'].each do |template|
    sh "erb -P -x -T '-' #{template} | ruby -c"
  end
end

desc 'Configure git to use the project hooks in .githooks/'
task :setup do
  sh 'git config core.hooksPath .githooks'
  puts 'Git hooks configured. Run "bundle exec rake setup" once per clone.'
end

desc 'Run all tests'
task :test => [:lint, :validate, :spec]

task :default => :test
