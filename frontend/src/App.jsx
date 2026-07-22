import { useState } from 'react';
import UploadReceipt from './components/UploadReceipt.jsx';
import ReceiptFormScreen from './components/ReceiptFormScreen.jsx';
import ReceiptList from './components/ReceiptList.jsx';
import Dashboard from './components/Dashboard.jsx';
import './App.css';

function App() {
  const [view, setView] = useState({ name: 'list' });

  function goToList() {
    setView({ name: 'list' });
  }

  return (
    <div className="app">
      <header className="app-header">
        <h1>Receipt Tracker</h1>
        <p className="app-tagline">Keep every receipt straight for tax time.</p>
      </header>

      <main className="app-content">
        {view.name === 'list' && (
          <ReceiptList
            onAddPhoto={() => setView({ name: 'upload' })}
            onAddManual={() => setView({ name: 'form', receiptId: null })}
            onEdit={(id) => setView({ name: 'form', receiptId: id })}
            onDashboard={() => setView({ name: 'dashboard' })}
          />
        )}

        {view.name === 'upload' && <UploadReceipt onDone={goToList} />}

        {view.name === 'form' && <ReceiptFormScreen receiptId={view.receiptId} onDone={goToList} />}

        {view.name === 'dashboard' && <Dashboard onDone={goToList} />}
      </main>
    </div>
  );
}

export default App;
