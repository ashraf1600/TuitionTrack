import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import Navbar from '../components/common/Navbar';
import TuitionBatchesHub from '../components/tutor/TuitionBatchesHub';
import TuitionBatchesModal from '../components/tutor/TuitionBatchesModal';
import { useAuth } from '../context/AuthContext';
import { api } from '../api/client';
import { notify } from '../utils/toast';

const asList = (data) => (Array.isArray(data) ? data : data?.results || []);

/**
 * TutorDashboard — Master View (Tuition Batches Hub)
 *
 * Implements the clean Master-Detail architecture for Tutors:
 * Screen 1: The "Tuition Batches Hub" (Master View)
 *   - Only displays a Grid of Tuition/Batch Cards with quick insights:
 *     1. Active students count
 *     2. Current cycle status ("Cycle 3: 5/12 Classes Done" + progress bar)
 *     3. Subtle Wallet snippet (earned / pending)
 *   - Floating Action Button (FAB) to "+ Create New Tuition"
 *   - Clicking any batch enters the dedicated "Tuition Manager Workspace" (/tuitions/:id).
 */
export default function TutorDashboard() {
  const navigate = useNavigate();
  const { user } = useAuth();

  const [tuitions, setTuitions] = useState([]);
  const [analytics, setAnalytics] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  // Modal for creating a new batch
  const [createModalOpen, setCreateModalOpen] = useState(false);

  const loadData = useCallback(async () => {
    setError('');
    try {
      setLoading(true);
      const [tuitionData, analyticsData] = await Promise.all([
        api.getTuitions().catch(() => []),
        api.getWalletAnalytics().catch(() => null),
      ]);
      setTuitions(asList(tuitionData));
      setAnalytics(analyticsData);
    } catch (err) {
      setError(err.message || 'Could not load your tuition batches.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleSelectTuition = (tuitionId) => {
    navigate(`/tuitions/${tuitionId}`);
  };

  const handleCreatedTuition = () => {
    loadData();
    notify.success('Tuition batch created successfully!');
  };

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900 flex flex-col font-sans selection:bg-indigo-500 selection:text-white">
      <Navbar />

      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6 sm:py-8">
        {/* ── Screen 1: The Tuition Batches Hub ── */}
        <TuitionBatchesHub
          tutorName={user?.name || user?.username}
          tutorCode={user?.tutor_code}
          tuitions={tuitions}
          analytics={analytics}
          loading={loading}
          error={error}
          onSelectTuition={handleSelectTuition}
          onCreateTuition={() => setCreateModalOpen(true)}
          onRefresh={loadData}
        />
      </main>

      {/* ── Create New Tuition Modal ── */}
      {createModalOpen && (
        <TuitionBatchesModal
          isOpen={createModalOpen}
          onClose={() => setCreateModalOpen(false)}
          onChanged={handleCreatedTuition}
          tuitionToEdit={null}
        />
      )}
    </div>
  );
}
