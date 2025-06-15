module.exports = {
  testEnvironment: 'jsdom',
  testMatch: ['**/test/**/*.test.js'],
  collectCoverage: false,  // Temporarily disable coverage to avoid minimatch error
  collectCoverageFrom: [
    'docker/services/ruby/public/js/monadic/**/*.js',
    'docker/services/ruby/public/js/monadic.js',
    '!**/node_modules/**'
  ],
  coverageDirectory: 'coverage',
  transform: {},
  testPathIgnorePatterns: ['/node_modules/'],
  setupFilesAfterEnv: ['./test/setup.js'],
  moduleDirectories: ['node_modules', 'docker/services/ruby/public/js'],
  moduleNameMapper: {
    // Improve module resolution for client-side JS
    '^monadic/(.*)$': '<rootDir>/docker/services/ruby/public/js/monadic/$1',
    '^monadic$': '<rootDir>/docker/services/ruby/public/js/monadic.js'
  },
  // Enable source map support for better stack traces
  globals: {
    '__DEV__': true
  }
};