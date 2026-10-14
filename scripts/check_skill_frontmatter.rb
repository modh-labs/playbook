#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that every skills/*/SKILL.md description is in a shape Claude Code reads:
# one line, or a block scalar (`>` or `|`). A quoted description that spans
# lines is valid YAML, but Claude Code shows the skill's title in its place.
#
# Usage: ruby scripts/check_skill_frontmatter.rb [repository root]

require "pathname"
require "yaml"

root = Pathname(ARGV.fetch(0, Pathname(__dir__).join(".."))).expand_path
failures = []

root.glob("skills/*/SKILL.md").sort.each do |path|
  slug = path.dirname.basename.to_s
  match = path.read(encoding: "UTF-8").match(/\A---\n(?<yaml>.*?)\n---\n/m)
  unless match
    failures << "#{slug}: missing frontmatter"
    next
  end

  begin
    metadata = YAML.safe_load(match[:yaml], aliases: false) || {}
  rescue Psych::SyntaxError => error
    failures << "#{slug}: #{error.message}"
    next
  end
  failures << "#{slug}: missing name or description" unless metadata["name"] && metadata["description"]

  description = match[:yaml].split(/^(?=[A-Za-z0-9_-]+:)/).find { |block| block.start_with?("description:") }
  next unless description

  first, *rest = description.chomp.lines
  block_scalar = first.match?(/\Adescription:\s*[>|][-+]?\s*\z/)
  if rest.any? && !block_scalar
    failures << "#{slug}: description spans #{rest.size + 1} lines without a > or | block"
  end
end

if failures.empty?
  puts("Checked #{root.glob("skills/*/SKILL.md").size} skills: frontmatter OK")
else
  puts(failures)
  abort("#{failures.size} skill(s) have frontmatter Claude Code cannot read")
end
