module config

import os
import strconv

// Config holds the settings shared by the client and server. Defaults are
// used when config.toml is missing or a key is absent.
pub struct Config {
pub mut:
	host     string = '127.0.0.1'
	port     int    = 1902
	no_color bool
}

// file_path is where the settings are read from, relative to the repo root.
pub const file_path = 'config.toml'

// load reads the small subset of TOML we care about (a [server] table with
// string and integer keys) and falls back to the defaults on any problem.
pub fn load() Config {
	mut cfg := Config{}
	if !os.exists(file_path) {
		return cfg
	}
	text := os.read_file(file_path) or {
		eprintln('[config] could not read ${file_path}: ${err.msg()}')
		return cfg
	}
	mut section := ''
	for raw_line in text.split_into_lines() {
		line := raw_line.trim_space()
		if line == '' || line.starts_with('#') {
			continue
		}
		if line.starts_with('[') && line.ends_with(']') {
			section = line[1..line.len - 1].trim_space()
			continue
		}
		eq := line.index('=') or { continue }
		key := line[..eq].trim_space()
		value := strip_value(line[eq + 1..])
		match '${section}.${key}' {
			'server.host' {
				if value != '' {
					cfg.host = value
				}
			}
			'server.port' {
				if p := strconv.atoi(value) {
					cfg.port = p
				}
			}
			'display.no_color' {
				cfg.no_color = value.to_lower() == 'true'
			}
			else {}
		}
	}
	return cfg
}

// strip_value removes surrounding quotes and any trailing comment.
fn strip_value(raw string) string {
	s := raw.trim_space()
	if s.len >= 2 {
		first := s[0]
		last := s[s.len - 1]
		if (first == `"` && last == `"`) || (first == `'` && last == `'`) {
			return s[1..s.len - 1]
		}
	}
	if i := s.index('#') {
		return s[..i].trim_space()
	}
	return s
}

// addr returns the host:port string used to dial/listen.
pub fn (c Config) addr() string {
	return '${c.host}:${c.port}'
}
