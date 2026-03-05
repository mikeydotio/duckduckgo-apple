# Create PR

Create a pull request for the current branch following repo conventions.

## Steps

1. **Gather context** (run in parallel):
   - `git status` (never use `-uall`)
   - `git diff HEAD` to check for uncommitted changes
   - `git log main..HEAD --oneline` to see all commits on the branch
   - `git diff main...HEAD` to see the full diff against main
   - Check if branch is pushed: `git log origin/<branch>..HEAD --oneline`

2. **Handle uncommitted changes**: If there are relevant uncommitted changes, ask the user whether to commit them first.

3. **Push if needed**: Push the branch with `git push -u origin <branch>`.

4. **Analyze changes**: Read the full diff carefully. Understand every file changed and what the PR accomplishes across ALL commits (not just the latest).

5. **Create the PR** using `gh pr create --draft` with the body formatted as below. Use a HEREDOC for the body. The title should be concise (under 70 chars). Always create as draft unless the user says otherwise.

## PR Body Format

All sections from the template must be present. Fill in content where applicable. For optional sections with nothing to add, keep the heading and write "N/A" or a brief note.

```
Task/Issue URL: <url if provided by user or in commit messages>
Tech Design URL:
CC:

### Description
<1-3 short paragraphs. Be specific about what changed and why. No fluff.>

### Testing Steps
<Numbered list. Assume reviewer is unfamiliar with this area.>

### Impact and Risks
<Low/Medium/High with brief justification>

#### What could go wrong?
<Specific scenarios and how they've been addressed>

### Quality Considerations
<Edge cases, performance, monitoring, privacy/security considerations. Write "N/A" if none apply.>

### Notes to Reviewer
<Anything specific reviewers should focus on. Write "N/A" if none.>

---
###### Internal references:
[Definition of Done](https://app.asana.com/0/1202500774821704/1207634633537039/f) | [Engineering Expectations](https://app.asana.com/0/59792373528535/199064865822552) | [Tech Design Template](https://app.asana.com/0/59792373528535/184709971311943)
```

## Guidelines

- Keep ALL sections from the template — never remove them.
- Keep description factual and concise — match the tone of recent merged PRs in the repo.
- For the Task/Issue URL, check commit messages, branch name, or ask the user.
- Return the PR URL when done.
