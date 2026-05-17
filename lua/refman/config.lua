return {
	log_level = "verbose",
	doi_styles = {
		{
			name = "DIN 1505-2 (German)",
			apis = {
				{
					url = "https://citation.doi.org/format?doi={doi}&style={style}&lang={lang}",
					style = "din-1505-2",
					lang = "de-DE"
				}
			}
		},
		{
			name = "Chicago Notes-Bibliography 17th ed.",
			apis = {
				{
					url = "https://citation.doi.org/format?doi={doi}&style={style}&lang={lang}",
					style = "chicago-notes-bibliography-17th-edition",
					lang = "de-DE"
				},
				{
					url = "https://citation.doi.org/format?doi={doi}&style={style}&lang={lang}",
					style = "chicago-notes-bibliography-17th-edition",
					lang = "en-US"
				}
			}
		},
		{
			name = "MLA (8th ed.)",
			apis = {
				{
					url = "https://citation.doi.org/format?doi={doi}&style={style}&lang={lang}",
					style = "modern-language-association-8th-edition",
					lang = "de-DE"
				},
				{
					url = "https://citation.doi.org/format?doi={doi}&style={style}&lang={lang}",
					style = "modern-language-association-8th-edition",
					lang = "en-US"
				}
			}
		},
		{
			name = "APA 7th Edition",
			apis = {
				{
					url = "https://citation.doi.org/format?doi={doi}&style={style}&lang={lang}",
					style = "apa",
					lang = "en-US"
				}
			}
		}
	},

	isbn_styles = {
		{
			name = "DIN 1505-2 (German)",
			template = "{authors}: {title}. {publisher} {year}."
		},
		{
			name = "MLA",
			template = "{authors}. *{title}*. {publisher}, {year}."
		},
		{
			name = "Chicago",
			template = "{authors}. *{title}*. {publisher}, {year}."
		},
		{
			name = "APA",
			template = "{authors} ({year}). *{title}*. {publisher}."
		}
	}
}
