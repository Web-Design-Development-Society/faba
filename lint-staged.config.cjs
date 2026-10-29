const joinFiles = (files) => files.map((file) => `"${file}"`).join(' ');

module.exports = {
  '*.{ts,js,mjs}': (stagedFiles) => [
    `prettier --write ${joinFiles(stagedFiles)}`,
    // `eslint --max-warnings=0 --no-warn-ignored ${joinFiles(stagedFiles)}`,
  ],
  '*.{sql,md}': (stagedFiles) => [`prettier --write ${joinFiles(stagedFiles)}`],
};
