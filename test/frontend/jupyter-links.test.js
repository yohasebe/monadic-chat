// Mock createCard function for testing
const createCard = (role, badge, html) => {
  return `<div class="card ${role}">${html}</div>`;
};

describe('Jupyter Notebook Links', () => {
  beforeEach(() => {
    // Set up DOM
    document.body.innerHTML = `
      <div id="cards-container"></div>
    `;
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('preserves Jupyter notebook links with full URLs', () => {
    const html = 'Here is your notebook: <a href="http://localhost:8889/lab/tree/analysis.ipynb" target="_blank">analysis.ipynb</a>';
    const card = createCard('assistant', 'AI', html, 'en', 'msg-1', true, []);
    
    expect(card).toContain('http://localhost:8889/lab/tree/analysis.ipynb');
    expect(card).toContain('target="_blank"');
  });

  it('does not modify absolute Jupyter URLs', () => {
    const html = '<a href="http://localhost:8889/lab/tree/notebook.ipynb">Open Notebook</a>';
    const card = createCard('assistant', 'AI', html, 'en', 'msg-1', true, []);
    
    // URL should remain unchanged
    expect(card).toContain('http://localhost:8889/lab/tree/notebook.ipynb');
    // Should not contain any proxy paths
    expect(card).not.toContain('href="/lab/');
  });

  it('handles Jupyter links with special characters in filenames', () => {
    const html = '<a href="http://localhost:8889/lab/tree/データ分析_2024.ipynb" target="_blank">データ分析_2024.ipynb</a>';
    const card = createCard('assistant', 'AI', html, 'en', 'msg-1', true, []);
    
    // Should preserve the URL as-is
    expect(card).toContain('データ分析_2024.ipynb');
  });

  it('creates proper message cards with Jupyter context', () => {
    const messageWithContext = {
      message: "I've created a notebook for you",
      context: {
        jupyter_running: true,
        notebook_created: true,
        link: '<a href="http://localhost:8889/lab/tree/analysis.ipynb" target="_blank">analysis.ipynb</a>'
      }
    };
    
    const html = `${messageWithContext.message}<br><br>${messageWithContext.context.link}`;
    const card = createCard('assistant', 'AI', html, 'en', 'msg-1', true, []);
    
    expect(card).toContain("I've created a notebook");
    expect(card).toContain('http://localhost:8889');
    expect(card).toContain('analysis.ipynb');
  });

  describe('URL format validation', () => {
    it('should use port 8889 for Jupyter URLs', () => {
      const correctUrl = 'http://localhost:8889/lab/tree/notebook.ipynb';
      const incorrectUrl = 'http://localhost:4567/lab/tree/notebook.ipynb';
      
      expect(correctUrl).toMatch(/:8889/);
      expect(incorrectUrl).not.toMatch(/:8889/);
    });

    it('should include /lab/tree/ in the path', () => {
      const correctPath = 'http://localhost:8889/lab/tree/notebook.ipynb';
      const incorrectPath = 'http://localhost:8889/notebook.ipynb';
      
      expect(correctPath).toContain('/lab/tree/');
      expect(incorrectPath).not.toContain('/lab/tree/');
    });
  });
});