/**
 * Jest configuration for no-mock UI tests (relocated)
 */

module.exports = {
  testEnvironment: 'jsdom',
  testMatch: [
    '**/test/frontend/no-mock/**/*.test.js'
  ],
  setupFilesAfterEnv: [],  // No global mocks
  moduleNameMapper: {
    '\\.(css|less|scss|sass)$': '<rootDir>/test/mocks/styleMock.js'
  },
  testPathIgnorePatterns: [
    '/node_modules/',
    '/test/frontend/[^/]+\\.test\\.js$'  // Ignore old mock-based tests
  ],
  coveragePathIgnorePatterns: [
    '/node_modules/',
    '/test/frontend/support/',
    '/test/helpers.js',
    '/test/setup.js'
  ],
  collectCoverageFrom: [
    'docker/services/ruby/public/js/**/*.js',
    '!docker/services/ruby/public/js/vendor/**',
    '!docker/services/ruby/public/js/**/*.min.js'
  ],
  transformIgnorePatterns: [
    'node_modules/(?!(ws)/)'
  ],
  testTimeout: 10000,
  verbose: true
};
