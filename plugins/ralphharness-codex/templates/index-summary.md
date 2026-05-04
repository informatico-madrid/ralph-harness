---
type: index-summary
generated: true
indexed: {{TIMESTAMP}}
---

# Codebase Index

## Overview

<!-- markdownlint-disable MD055 MD056 -->
| Category | Count | Last Updated |
|----------|-------|--------------|
{{#each CATEGORIES}}
| {{name}} | {{count}} | {{lastUpdated}} |
{{/each}}
| **Total** | **{{TOTAL}}** | {{TIMESTAMP}} |
<!-- markdownlint-enable MD055 MD056 -->

## Components

### Controllers
{{#each CONTROLLERS}}
- [{{name}}](components/{{file}}) - {{purpose}}
{{/each}}

### Services
{{#each SERVICES}}
- [{{name}}](components/{{file}}) - {{purpose}}
{{/each}}

### Models
{{#each MODELS}}
- [{{name}}](components/{{file}}) - {{purpose}}
{{/each}}

### Helpers
{{#each HELPERS}}
- [{{name}}](components/{{file}}) - {{purpose}}
{{/each}}

### Migrations
{{#each MIGRATIONS}}
- [{{name}}](components/{{file}}) - {{purpose}}
{{/each}}

## External Resources

<!-- markdownlint-disable MD055 MD056 -->
| Resource | Type | Fetched |
|----------|------|---------|
{{#each EXTERNAL}}
| [{{name}}](external/{{file}}) | {{type}} | {{fetched}} |
{{/each}}
<!-- markdownlint-enable MD055 MD056 -->


## Index Settings

- **Excluded patterns**: {{EXCLUDES}}
- **Indexed paths**: {{PATHS}}
