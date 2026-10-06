import React, { useState } from 'react';
import { User, Phone, School, DollarSign, Calendar, Check, X, UserPlus, Power, Key } from 'lucide-react';
import StudentCredentialsModal from './StudentCredentialsModal';

export default function StudentRoster({
  students,
  selectedStudentId,
  tuitionTitle = '',
  onSelectStudent,
  onToggleActive,
  onOpenAddModal,
  loading,
}) {
  const [selectedStudentForCredentials, setSelectedStudentForCredentials] = useState(null);

  return (
    <>
      <div className="glass-panel p-6 rounded-2xl">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h3 className="text-lg font-bold text-slate-100 flex items-center gap-2">
              <User className="w-5 h-5 text-indigo-400" />
              {tuitionTitle ? `${tuitionTitle} Roster` : 'Student Roster'}
            </h3>
            <p className="text-xs text-slate-400">
              {students.length} {students.length === 1 ? 'student' : 'students'} {tuitionTitle ? 'enrolled in this tuition' : 'enrolled'}
            </p>
          </div>

          <button
            onClick={onOpenAddModal}
            className="px-3.5 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-medium text-xs flex items-center gap-1.5 shadow-md shadow-indigo-600/20 transition"
          >
            <UserPlus className="w-4 h-4" />
            <span>Add Student</span>
          </button>
        </div>

        {loading ? (
          <div className="space-y-3">
            {[1, 2, 3].map((i) => (
              <div key={i} className="h-20 rounded-xl bg-slate-800/40 animate-pulse" />
            ))}
          </div>
        ) : students.length === 0 ? (
          <div className="text-center py-10 px-4 rounded-xl border border-dashed border-slate-800 text-slate-400">
            <User className="w-10 h-10 mx-auto text-slate-600 mb-2" />
            <p className="text-sm font-semibold text-slate-300">
              {tuitionTitle ? `No students in ${tuitionTitle} yet` : 'No students yet'}
            </p>
            <p className="text-xs text-slate-500 mt-1 mb-4">
              {tuitionTitle
                ? 'Add or assign students to this tuition to begin tracking attendance.'
                : 'Add your first student to automatically initialize Cycle #1'}
            </p>
            <button
              onClick={onOpenAddModal}
              className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-medium text-xs transition"
            >
              {tuitionTitle ? `Add Student to ${tuitionTitle}` : 'Add Student Now'}
            </button>
          </div>
        ) : (
          <div className="space-y-2.5 max-h-[500px] overflow-y-auto pr-1">
            {students.map((student) => {
              const isSelected = String(selectedStudentId) === String(student.student_id ?? student.id);
              const profile = student.profile || {};

              return (
                <div
                  key={String(student.student_id ?? student.id)}
                  onClick={() => onSelectStudent(String(student.student_id ?? student.id))}
                  className={`p-3.5 rounded-xl border cursor-pointer transition-all duration-200 ${
                    isSelected
                      ? 'bg-indigo-950/40 border-indigo-500/60 shadow-lg shadow-indigo-500/10'
                      : 'bg-slate-800/30 border-slate-700/50 hover:bg-slate-800/60 hover:border-slate-600'
                  }`}
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex-1 min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <h4 className="text-sm font-bold text-slate-100 truncate">
                          {student.full_name}
                        </h4>
                        <span className="text-[11px] font-mono text-slate-400 bg-slate-800 px-1.5 py-0.5 rounded">
                          @{student.username}
                        </span>
                        {student.must_change_password && (
                          <span
                            className="text-[10px] text-amber-300 bg-amber-500/10 border border-amber-500/20 px-1.5 py-0.5 rounded"
                            title="This student still has a temporary password and will choose their own at next sign-in"
                          >
                            Temporary password
                          </span>
                        )}
                        {!student.is_active && (
                          <span className="text-[10px] font-semibold text-rose-400 bg-rose-950/60 px-1.5 py-0.5 rounded border border-rose-800/40">
                            Inactive
                          </span>
                        )}
                      </div>

                      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 mt-1.5 text-xs text-slate-400">
                        {profile.grade_level && (
                          <span className="flex items-center gap-1">
                            <School className="w-3.5 h-3.5 text-slate-500" />
                            {profile.grade_level}
                          </span>
                        )}
                        {profile.institution && <span className="truncate">{profile.institution}</span>}
                        {student.phone && (
                          <span className="flex items-center gap-1">
                            <Phone className="w-3.5 h-3.5 text-slate-500" />
                            {student.phone}
                          </span>
                        )}
                      </div>
                    </div>

                    <div className="flex items-center gap-1.5 flex-shrink-0">
                      {/* Credentials / Password Button */}
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          setSelectedStudentForCredentials(student);
                        }}
                        title="Give this student a new temporary password"
                        className="p-1.5 rounded-lg border border-amber-500/20 bg-amber-500/10 text-amber-400 hover:bg-amber-500/20 hover:border-amber-500/40 transition flex items-center gap-1 text-[11px] font-semibold"
                      >
                        <Key className="w-3.5 h-3.5" />
                        <span className="hidden sm:inline">Reset password</span>
                      </button>

                      {/* Toggle Active Button */}
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          onToggleActive(String(student.student_id ?? student.id));
                        }}
                        title={student.is_active ? 'Deactivate Student' : 'Activate Student'}
                        className={`p-1.5 rounded-lg border transition ${
                          student.is_active
                            ? 'text-emerald-400 border-emerald-500/20 bg-emerald-500/10 hover:bg-rose-500/20 hover:text-rose-400 hover:border-rose-500/30'
                            : 'text-slate-500 border-slate-700 bg-slate-800 hover:text-emerald-400 hover:border-emerald-500/30'
                        }`}
                      >
                        <Power className="w-4 h-4" />
                      </button>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      <StudentCredentialsModal
        isOpen={Boolean(selectedStudentForCredentials)}
        onClose={() => setSelectedStudentForCredentials(null)}
        student={selectedStudentForCredentials}
      />
    </>
  );
}
