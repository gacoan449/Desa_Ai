module.exports = {
  env: { es2021: true, node: true },
  extends: ["eslint:recommended"],
  parserOptions: { ecmaVersion: 2022 },
  rules: {
    "no-unused-vars": ["warn", { argsIgnorePattern: "^_", varsIgnorePattern: "^_" }],
    "no-console": "off",
    "no-undef": "off"
  }
};
