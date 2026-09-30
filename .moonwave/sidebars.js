// Sidebar for the Docs section. Moonwave copies this file into its Docusaurus project.
// Every entry is a file name in docs/ without the .md.
module.exports = {
	docs: [
		"intro",
		{
			type: "category",
			label: "Internals (in Spanish)",
			items: ["math", "optimization", "editable-image"],
		},
	],
}
