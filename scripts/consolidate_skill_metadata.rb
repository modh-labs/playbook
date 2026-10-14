#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "pathname"
require "yaml"

root = Pathname(__dir__).join("..").expand_path
skills_root = root.join("skills")
catalog_path = root.join("skill-catalog.json")
catalog =
  if catalog_path.file?
    JSON.parse(catalog_path.read).fetch("skills", {})
  else
    {}
  end

skills_root.children.select(&:directory?).sort.each do |skill_dir|
  skill_path = skill_dir.join("SKILL.md")
  next unless skill_path.file?

  source = skill_path.read
  match = source.match(/\A---\n(?<yaml>.*?)\n---\n(?<body>.*)\z/m)
  abort("#{skill_path} is missing valid frontmatter") unless match

  begin
    metadata = YAML.safe_load(match[:yaml], aliases: false) || {}
  rescue Psych::SyntaxError => error
    abort("#{skill_path}: #{error.message}")
  end
  name = metadata.delete("name")
  description = metadata.delete("description")
  abort("#{skill_path} requires name and description") unless name && description

  slug = skill_dir.basename.to_s
  if metadata.empty? && !catalog.key?(slug)
    historical, _error, status = Open3.capture3("git", "-C", root.to_s, "show", "HEAD:skills/#{slug}/SKILL.md")
    if status.success?
      historical_match = historical.match(/\A---\n(?<yaml>.*?)\n---/m)
      historical_metadata = historical_match ? YAML.safe_load(historical_match[:yaml], aliases: false) : {}
      historical_metadata&.delete("name")
      historical_metadata&.delete("description")
      metadata = historical_metadata unless historical_metadata.nil?
    end
  end

  if metadata.empty? && !catalog.key?(slug)
    metadata = {
      "tier" => "process",
      "icon" => "workflow",
      "title" => name.to_s.split("-").map(&:capitalize).join(" "),
      "seo_title" => "#{name.to_s.split("-").map(&:capitalize).join(" ")} | MODH Engineering Skill",
      "seo_description" => description,
      "keywords" => name.to_s.split("-"),
      "difficulty" => "intermediate",
      "related_chapters" => [],
      "related_tools" => [],
    }
  end

  catalog[slug] = metadata unless metadata.empty?
  # Keep name and description as written. to_yaml re-quotes a folded description
  # across lines, which Claude Code reads as missing.
  kept = match[:yaml].split(/^(?=[A-Za-z0-9_-]+:)/).select { |block| block.start_with?("name:", "description:") }
  skill_path.write("---\n#{kept.map { |block| "#{block.chomp}\n" }.join}---\n#{match[:body]}")
end

catalog_path.write(
  JSON.pretty_generate(
    {
      "$schema" => "./skill-catalog.schema.json",
      "generated_at" => "2026-07-31",
      "skills" => catalog,
    },
  ) + "\n",
)

puts("Consolidated #{catalog.length} website metadata records into skill-catalog.json")
