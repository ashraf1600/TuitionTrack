import React from 'react';
import TutorWorkspaceView from './TutorWorkspaceView';

/**
 * TutorDetailView — Alias and wrapper around TutorWorkspaceView
 * for backwards compatibility with any existing student dashboard routes.
 */
export default function TutorDetailView(props) {
  return <TutorWorkspaceView {...props} />;
}
