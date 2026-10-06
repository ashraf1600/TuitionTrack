"""
Tenant-Scoped Base ViewSet

All ViewSets in TuitionTrack should inherit from TenantScopedViewSet.
It guarantees that:
  - Tutors only see their own data (tutor=request.user)
  - Students only see data scoped to them (student=request.user)
  - Data creation automatically binds tutor=request.user

This is the core multi-tenancy enforcement layer. No individual view
needs to manually filter by tutor — it's handled here globally.
"""
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from apps.authentication.permissions import IsTutorOrStudent


class TenantScopedViewSet(viewsets.ModelViewSet):
    """
    Base ViewSet providing automatic multi-tenant query scoping.

    Subclasses MUST define:
        - queryset: the base unfiltered queryset
        - serializer_class: the serializer to use

    Subclasses MAY override:
        - get_queryset() for additional custom filtering
        - perform_create() for additional creation-time logic
    """
    permission_classes = [IsAuthenticated, IsTutorOrStudent]

    def get_queryset(self):
        """
        Automatically scope queries to the logged-in user's tenant.
        Tutors see all their data; Students see only data assigned to them.
        """
        user = self.request.user
        qs = super().get_queryset()

        if user.role == 'TUTOR':
            # Tutors see everything they own
            if hasattr(qs.model, 'tutor'):
                return qs.filter(tutor=user)

        elif user.role == 'STUDENT':
            # Students see only data assigned to them
            if hasattr(qs.model, 'student'):
                return qs.filter(student=user)

        return qs.none()

    def perform_create(self, serializer):
        """
        Automatically attach the logged-in tutor as the owner on create.
        """
        user = self.request.user
        if user.role == 'TUTOR':
            serializer.save(tutor=user)
        else:
            serializer.save()
