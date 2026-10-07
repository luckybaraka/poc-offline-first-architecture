from django.urls import path

from . import views

urlpatterns = [
    path("health/", views.HealthView.as_view()),
    path("sync/push/", views.PushView.as_view()),
    path("sync/pull/", views.PullView.as_view()),
    path("sync/events/", views.EventsView.as_view()),
    path("records/", views.RecordsView.as_view()),
]
