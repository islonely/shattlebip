module util

// merge_strings combines to strings spanning multiple lines.
pub fn merge_strings(s1 string, s2 string, padding int, divider string) string {
	mut lines1 := s1.split_into_lines()
	mut lines2 := s2.split_into_lines()
	if lines1.len == 0 {
		lines1 = ['']
	}
	if lines2.len == 0 {
		lines2 = ['']
	}
	for i := 0; i < lines1.len && i < lines2.len; i++ {
		lines1[i] = lines1[i] + ' '.repeat(padding) + divider + ' '.repeat(padding) + lines2[i]
	}
	return lines1.join('\n')
}
