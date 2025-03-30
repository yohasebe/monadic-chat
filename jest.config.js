module.exports = {
  testEnvironment: 'jsdom',
  testMatch: ['**/test/**/*.test.js'],
  collectCoverage: true,
  collectCoverageFrom: [
    'docker/services/ruby/public/js/monadic/**/*.js',
    'docker/services/ruby/public/js/monadic.js',
    '!**/node_modules/**'
  ],
  coverageDirectory: 'coverage',
  transform: {},
  testPathIgnorePatterns: ['/node_modules/'],
  setupFilesAfterEnv: ['./test/setup.js'],
  moduleDirectories: ['node_modules', 'docker/services/ruby/public/js']
};